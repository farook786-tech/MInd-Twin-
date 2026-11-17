'use strict';

const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { getMessaging } = require('firebase-admin/messaging');

if (!getApps().length) initializeApp();

module.exports = {
  db: () => getFirestore(),
  auth: () => getAuth(),
  messaging: () => getMessaging(),
};
