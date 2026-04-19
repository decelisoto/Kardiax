// functions/index.js
//
// Deploy with: firebase deploy --only functions
//
// Environment variables (set via Firebase CLI before deploying):
//   firebase functions:secrets:set SMTP_USER      (e.g. your Gmail address)
//   firebase functions:secrets:set SMTP_PASS      (app password)
//   firebase functions:secrets:set TWILIO_SID
//   firebase functions:secrets:set TWILIO_TOKEN
//   firebase functions:secrets:set TWILIO_FROM    (E.164 number, e.g. +15550001234)

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();
const db = admin.firestore();

// ── Secrets ────────────────────────────────────────────────────────────────
const SMTP_USER = defineSecret("SMTP_USER");
const SMTP_PASS = defineSecret("SMTP_PASS");

// ── 1. sendCircleInvite ────────────────────────────────────────────────────
// Callable from the Flutter app. Sends an invite email (and optional SMS)
// to the new circle member.
exports.sendCircleInvite = onCall(
  { secrets: [SMTP_USER, SMTP_PASS] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required");

    const { token, toEmail, toPhone, toName, fromName } = request.data;
    if (!token || !toEmail) {
      throw new HttpsError("invalid-argument", "token and toEmail are required");
    }

    const appStoreLink = "https://apps.apple.com/app/kardiax"; // update when live
    const subject = `${fromName} added you to their emergency circle on KardiaxX`;
    const body = `
Hi ${toName || "there"},

${fromName} has added you to their KardiaxX emergency circle.
If their heart monitor detects an arrhythmia and they don't cancel the alarm within 30 seconds, you'll receive an emergency notification.

To accept this invite:
1. Download KardiaxX: ${appStoreLink}
2. Create an account with this email address (${toEmail})
3. Open the Invites tab — your invite will be waiting there

Your invite code: ${token}

— The KardiaxX Team
    `.trim();

    // Send email
    const transporter = nodemailer.createTransport({
      service: "gmail",
      auth: { user: SMTP_USER.value(), pass: SMTP_PASS.value() },
    });

    await transporter.sendMail({
      from: `"KardiaxX" <${SMTP_USER.value()}>`,
      to: toEmail,
      subject,
      text: body,
    });

    return { success: true };
  }
);

// ── 2. onAlertFired ────────────────────────────────────────────────────────
// Triggered when a new alert doc is created under users/{userId}/alerts/{alertId}.
// Sends FCM push notifications to all accepted circle members.
exports.onAlertFired = onDocumentCreated(
  "users/{userId}/alerts/{alertId}",
  async (event) => {
    const alert = event.data.data();

    // Only notify when the alarm actually fired (not cancelled, not stale).
    if (!alert.circleNotified || alert.cancelled || alert.dropped) return;

    const userId = event.params.userId;
    const alertId = event.params.alertId;

    // Get patient's display name.
    const userDoc = await db.collection("users").doc(userId).get();
    const patientName = userDoc.data()?.displayName || "Your contact";

    // Find accepted circle members with linked UIDs.
    const circleSnap = await db
      .collection("users").doc(userId).collection("circle")
      .where("inviteStatus", "==", "accepted")
      .get();

    const tokens = [];
    for (const memberDoc of circleSnap.docs) {
      const member = memberDoc.data();
      if (!member.linkedUid) continue;
      const memberUserDoc = await db.collection("users").doc(member.linkedUid).get();
      const fcmToken = memberUserDoc.data()?.fcmToken;
      if (fcmToken) tokens.push(fcmToken);
    }

    if (tokens.length === 0) return;

    const message = {
      tokens,
      notification: {
        title: "🚨 Cardiac Alert",
        body: `${patientName} may need help — ${alert.type || "arrhythmia"} detected`,
      },
      data: {
        type: "cardiac_alert",
        alertId,
        userId,
        patientName,
        alertType: alert.type || "Arrhythmia",
      },
      android: { priority: "high" },
      apns: { payload: { aps: { sound: "default", badge: 1 } } },
    };

    const result = await admin.messaging().sendEachForMulticast(message);
    console.log(`Sent ${result.successCount}/${tokens.length} notifications for alert ${alertId}`);
  }
);

// ── 3. heartbeatWatchdog ───────────────────────────────────────────────────
// Runs every 5 minutes. Finds users whose device was connected but hasn't
// sent a heartbeat in >5 minutes, which indicates the phone may have died
// or lost power mid-session. Creates a "device_lost" alert so circle members
// are notified even if the alarm countdown never completed.
exports.heartbeatWatchdog = onSchedule("every 5 minutes", async () => {
  const cutoff = new Date(Date.now() - 5 * 60 * 1000);

  const staleSnap = await db.collection("users")
    .where("bleConnected", "==", true)
    .where("lastHeartbeat", "<", admin.firestore.Timestamp.fromDate(cutoff))
    .get();

  for (const userDoc of staleSnap.docs) {
    const userId = userDoc.id;
    const userData = userDoc.data();

    await db.collection("users").doc(userId).collection("alerts").add({
      type: "device_lost",
      confidence: 1.0,
      hr: 0,
      circleNotified: true,
      cancelled: false,
      dropped: false,
      patientName: userData.displayName || "Unknown",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Mark device as disconnected to avoid repeat triggers.
    await userDoc.ref.update({ bleConnected: false });
  }
});

// ── 4. onInviteAccepted ────────────────────────────────────────────────────
// Triggered when an invite's status changes to 'accepted'.
// Links the acceptor's UID back to the circle doc so onAlertFired can find them.
exports.onInviteAccepted = onDocumentUpdated(
  "invites/{token}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();

    if (before.status === after.status) return; // no status change
    if (after.status !== "accepted") return;

    const { fromUid, circleDocId, acceptedByUid } = after;
    if (!fromUid || !circleDocId || !acceptedByUid) return;

    await db
      .collection("users").doc(fromUid)
      .collection("circle").doc(circleDocId)
      .update({
        linkedUid: acceptedByUid,
        inviteStatus: "accepted",
        status: "online",
      });

    // Notify the patient that someone accepted their invite.
    const patientDoc = await db.collection("users").doc(fromUid).get();
    const patientToken = patientDoc.data()?.fcmToken;
    const acceptorDoc = await db.collection("users").doc(acceptedByUid).get();
    const acceptorName = acceptorDoc.data()?.displayName || "Someone";

    if (patientToken) {
      await admin.messaging().send({
        token: patientToken,
        notification: {
          title: "Circle updated",
          body: `${acceptorName} accepted your circle invite`,
        },
        data: { type: "invite_accepted" },
      });
    }
  }
);
