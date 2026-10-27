# Guess My Number — Full Setup Guide

This guide walks you through creating a brand-new Firebase project, linking it to a fresh Flutter project, and deploying to Vercel. Follow every step in order. Don't skip.

**Total time**: ~30 minutes if you have the CLI tools installed, ~45 minutes if you need to install them.

---

## Phase 0 — Prerequisites

Install these once. You only do this on a new machine.

### 0.1 Flutter SDK

You already have this (you've been running `flutter build web`). Skip.

### 0.2 Node.js + npm

Vercel's CLI runs on Node. Download from https://nodejs.org/ (LTS version) and install. Verify:

```
node --version
npm --version
```

Both should print a version number.

### 0.3 Firebase CLI

Install globally:

```
npm install -g firebase-tools
```

Verify:

```
firebase --version
```

### 0.4 FlutterFire CLI

Install globally:

```
dart pub global activate flutterfire_cli
```

Verify:

```
flutterfire --version
```

If `flutterfire` is not found, add `C:\Users\user\AppData\Local\Pub\Cache\bin` to your PATH (Windows) or `~/.pub-cache/bin` (macOS/Linux). Restart your terminal after.

### 0.5 Git + GitHub CLI (optional but recommended)

You already have Git. For GitHub CLI: https://cli.github.com/ — install and run `gh auth login` once.

---

## Phase 1 — Create the new Firebase project

### 1.1 Go to the Firebase console

Open https://console.firebase.google.com/ in your browser. Sign in with your Google account.

### 1.2 Create the project

1. Click **Add project**
2. Project name: `guessmynumber` (or pick anything — the project ID is what matters)
3. Google Analytics: **Disable** for now (we don't need it for v1)
4. Click **Create project**
5. Wait ~30 seconds for provisioning

### 1.3 Note the project ID

After creation, click the gear icon → **Project settings**. Note the **Project ID** — it'll look like `guessmynumber` or `guessmynumber-12345` (Firebase appends a random suffix if `guessmynumber` is taken).

You'll use this ID in every CLI command below.

### 1.4 Set the Firestore region to eur3 (Europe)

1. In the Firebase console left sidebar, click **Firestore Database**
2. Click **Create database**
3. **Location**: select `eur3 (europe-west)`
4. **Security rules**: select **Production mode** (we'll deploy our own rules later)
5. Click **Create**

Wait ~30 seconds for provisioning.

### 1.5 Enable Anonymous authentication

1. In the Firebase console left sidebar, click **Authentication**
2. Click **Get started**
3. Tab **Sign-in method** → click **Anonymous** → **Enable** → **Save**

### 1.6 Add authorized domains

While still in Authentication → Settings → **Authorized domains**:

- `localhost` should already be there (default)
- After you deploy to Vercel (Phase 5), come back here and add your Vercel domain (e.g. `guessmynumber.vercel.app`)

---

## Phase 2 — Link the Flutter project to Firebase

### 2.1 Authenticate the Firebase CLI

In a terminal:

```
firebase login
```

This opens a browser window. Sign in with the same Google account you used in Phase 1.

### 2.2 Copy the project files

The Dart files I delivered are at `/home/z/my-project/download/guessmynumber/`. Copy the entire folder to your desktop:

```
C:\Users\user\Desktop\guessmynumber\
```

The folder should contain:
- `pubspec.yaml`
- `firestore.rules`
- `firestore.indexes.json`
- `web/index.html`
- `lib/` (all the Dart source files)
- `SETUP.md` (this file)

### 2.3 Install Flutter dependencies

```
cd C:\Users\user\Desktop\guessmynumber
flutter pub get
```

This downloads `firebase_core`, `firebase_auth`, `cloud_firestore` and the other dependencies declared in `pubspec.yaml`. Takes ~30 seconds.

### 2.4 Run flutterfire configure

```
flutterfire configure
```

The CLI will prompt you:

1. **Select a Firebase project**: use arrow keys to select `guessmynumber` (the project you created in Phase 1). Press Enter.
2. **Select platforms**: arrow-key to `web`, press Space to select, press Enter to confirm. (We're web-only for v1.)
3. **Firebase app id**: leave blank (auto-generated).

The CLI will:
- Create a web app in your Firebase project
- Generate `lib/firebase_options.dart` (overwriting the placeholder)
- Create `firebase.json` and `.firebaserc` in the project root

Verify `lib/firebase_options.dart` was generated:

```
type lib\firebase_options.dart
```

You should see real values (not `REPLACE_ME_RUN_FLUTTERFIRE_CONFIGURE`).

### 2.5 Test the app locally

```
flutter build web --release
cd build\web
python -m http.server 8080
```

(If `python` isn't recognized, try `py -m http.server 8080`.)

Open `http://localhost:8080` in Chrome. Hard refresh: **Ctrl+Shift+R**.

You should see:
1. A loading spinner (teal on white)
2. Then the home screen: "Guess My Number" with three cards — Play Solo, Host a New Game, Join a Game

If you see a **red error screen**, read the message. It will tell you exactly what's wrong (most likely: anonymous auth not enabled, or a domain issue). Fix it and refresh.

If you see a **white screen**, press F12 → Console. Look for `[boot]` lines. The message will tell you what failed.

**Don't move on to Phase 3 until you see the home screen.**

---

## Phase 3 — Deploy Firestore rules + indexes

### 3.1 Initialize Firebase in the project

```
cd C:\Users\user\Desktop\guessmynumber
firebase init
```

The CLI will prompt:

1. **Features**: use arrow keys + Space to select **Firestore**. Press Enter.
2. **Use an existing project**: select `guessmynumber`. Press Enter.
3. **Firestore Rules file**: press Enter to accept default `firestore.rules`
4. **Firestore Indexes file**: press Enter to accept default `firestore.indexes.json`

This creates `firebase.json` (or updates it) pointing at the rules and indexes files I delivered.

### 3.2 Deploy the rules

```
firebase deploy --only firestore:rules
```

Wait ~10 seconds. You should see `✔ Deploy complete!`.

### 3.3 Deploy the indexes

```
firebase deploy --only firestore:indexes
```

Wait ~2-5 minutes for indexes to build. You can check progress in the Firebase console → Firestore → Indexes tab.

### 3.4 Verify rules deployed

Go to Firebase console → Firestore → **Rules** tab. You should see the rules from `firestore.rules` (with the v4 schema comments about the `round` field).

---

## Phase 4 — Create the GitHub repo

### 4.1 Initialize git locally

```
cd C:\Users\user\Desktop\guessmynumber
git init
git add .
git commit -m "Initial commit: Guess My Number v1"
```

### 4.2 Create a .gitignore

Create a file called `.gitignore` in the project root with this content:

```
# Flutter / Dart
build/
.dart_tool/
.packages
.flutter-plugins
.flutter-plugins-dependencies
.pub-cache/
.pub/
ios/Pods/
android/.gradle/

# IntelliJ / VS Code
.idea/
.vscode/
*.iml
*.ipr
*.iws

# macOS
.DS_Store

# Firebase
# Note: we DO commit firebase_options.dart because it only contains
# public API keys (safe to ship). The Firebase Auth secrets live in
# the Firebase console, not in this file.

# Vercel
.vercel/

# Misc
*.log
```

Then:

```
git add .gitignore
git commit -m "Add .gitignore"
```

### 4.3 Create the GitHub repo

**Option A — GitHub CLI (recommended)**:

```
gh repo create guessmynumber --public --source=. --push
```

This creates a public repo named `guessmynumber`, links it as origin, and pushes your local commits.

**Option B — Manual**:

1. Go to https://github.com/new
2. Repository name: `guessmynumber`
3. Public, no README, no .gitignore (we have our own)
4. Click **Create repository**
5. Copy the push commands GitHub shows you (something like):
   ```
   git remote add origin https://github.com/YOUR_USERNAME/guessmynumber.git
   git branch -M main
   git push -u origin main
   ```

Verify on GitHub: refresh your repo page, you should see all the project files.

---

## Phase 5 — Deploy to Vercel

### 5.1 Decide your deployment strategy

You have two options for what Vercel serves:

**Option A (recommended): Vercel builds from source**
- Vercel clones your repo, runs `flutter build web --release`, and serves `build/web/`
- Pros: every push auto-deploys. Clean.
- Cons: requires Flutter build environment on Vercel — uses a community-build framework

**Option B: You build locally, commit `build/web/` to the repo**
- You build locally, copy `build/web/` into a `docs/` or `public/` folder in the repo, commit and push
- Vercel serves that folder as static files
- Pros: simple, no build environment needed
- Cons: you must rebuild + commit + push for every code change

We'll set up **Option A** (the proper way). If it doesn't work, fall back to Option B (instructions at the end of this section).

### 5.2 Install Vercel CLI

```
npm install -g vercel
```

Verify:

```
vercel --version
```

### 5.3 Login to Vercel

```
vercel login
```

Follow the prompts (email or GitHub).

### 5.4 Create `vercel.json` for Flutter builds

In the project root, create `vercel.json` with:

```json
{
  "buildCommand": "curl -sL https://flutter.dev | bash -s -- --version stable && export PATH=\"$PATH:$HOME/flutter/bin\" && flutter pub get && flutter build web --release --no-tree-shake-icons",
  "outputDirectory": "build/web",
  "framework": null,
  "installCommand": "echo 'skip'"
}
```

This tells Vercel: install Flutter on the build server, build the web app, and serve `build/web/` as static files.

Commit it:

```
git add vercel.json
git commit -m "Add Vercel build config"
git push
```

### 5.5 Deploy

```
vercel
```

First time, it will ask:
- **Set up and deploy?** Y
- **Which scope?** pick your account
- **Link to existing project?** N
- **Project name?** `guessmynumber`
- **In which directory?** `.` (just press Enter)
- **Want to modify settings?** N

Vercel will clone the repo, run the build command, and deploy. Takes ~3-5 minutes (Flutter install is slow on first build).

When done, it prints a URL like `https://guessmynumber-abc123.vercel.app`. Open it — you should see your home screen.

### 5.6 Add the Vercel domain to Firebase authorized domains

1. Copy your Vercel URL (e.g. `guessmynumber-abc123.vercel.app`)
2. Go to Firebase console → Authentication → **Settings** → **Authorized domains**
3. Click **Add domain** → paste the Vercel hostname (without `https://`)
4. Click **Add**

If you skip this, anonymous auth will fail on the production site with `auth/unauthorized-domain`.

### 5.7 Production deploy

The previous step deployed a preview URL. To deploy to production:

```
vercel --prod
```

This deploys to your "production" URL (e.g. `https://guessmynumber.vercel.app` if the name is available, or whatever Vercel assigned). Add this domain to Firebase authorized domains too.

### 5.8 (Fallback) Option B — local build committed to repo

If Option A doesn't work (Vercel build fails, takes too long, etc.):

1. Build locally:
   ```
   flutter build web --release
   ```
2. Move `build/web/` to a new folder in your repo:
   ```
   xcopy /E /I /Y build\web docs
   ```
3. Commit and push:
   ```
   git add docs
   git commit -m "Deploy: static build"
   git push
   ```
4. In Vercel, set **Output Directory** to `docs` (via the Vercel dashboard → your project → Settings → Build & Output Settings).
5. Redeploy. Vercel serves the static files from `docs/`.

For every code change: rebuild locally, copy to `docs/`, commit, push. Vercel auto-deploys on push.

---

## Phase 6 — Smoke test

Open your production Vercel URL. Test these flows:

### 6.1 Solo mode (Daily Challenge)

1. Tap **Play Solo**
2. Tap **Daily Challenge**
3. Type a number, tap Submit
4. Verify feedback ("too low" / "too high" / "correct")
5. Win or lose
6. (On win) Enter your name → tap **Submit Score**
7. Verify the leaderboard shows your entry

### 6.2 Multiplayer (two browser windows)

1. **Window A** (host): tap **Host a New Game** → set up a room → copy the 6-char code
2. **Window B** (player, incognito): tap **Join a Game** → paste the code → enter name → Join
3. Player guesses. Host sees the guess in real time.
4. Play a full round until someone wins/loses.

### 6.3 Rematch (the bug we just fixed)

1. From the end-game dialog, host taps **New Game**
2. Host types a new secret → **Start Round**
3. Host sees "Waiting for player to accept..."
4. Player sees rematch prompt → **Keep Playing**
5. Both screens show fresh round, full lives, empty guess history
6. Play another round. Verify it works.
7. Repeat for 3+ consecutive rematches — this was the bug that failed in v3.

If all three flows work, you're done. 🎉

---

## Phase 7 — Phase 2 features (later)

Once v1 is stable on Vercel, we can add:

- **Google sign-in**: replace anonymous auth with Google. User accounts persist across devices.
- **Game history**: a new Firestore collection `users/{uid}/games` recording each completed game with timestamp, opponent, winner, guess count.
- **Race mode**: 2-5 players in one room, all guessing simultaneously, first to guess correctly wins. Requires new phase state machine and new UI.

Each Phase 2 feature should be developed and shipped independently so we can verify each works before stacking the next.

---

## Troubleshooting

### "White screen" on localhost or Vercel

1. Open F12 → Console
2. Look for `[boot]` lines
3. `[boot] step 1 FAILED: ...` → Firebase config problem. Check `lib/firebase_options.dart` has real values (not `REPLACE_ME_...`)
4. `[boot] step 2 FAILED (non-fatal): ...` → Anonymous auth problem. Check Firebase console → Authentication → Sign-in method → Anonymous is enabled
5. `permission-denied` → Firestore rules not deployed. Run `firebase deploy --only firestore:rules`
6. `auth/unauthorized-domain` → Add the domain to Firebase console → Authentication → Settings → Authorized domains

### "RenderFlex overflow" or layout issues

This is a UI bug, not a setup problem. Tell me which screen and I'll fix the layout.

### Multiplayer doesn't update in real time

Check your Firestore rules — the player needs `allow read` on the room doc, which our rules provide. Also check the Firestore console to see if the room doc is actually being written.

### Daily leaderboard shows "Check your connection"

This means the Firestore read failed. Most likely cause: rules not deployed. Run:
```
firebase deploy --only firestore:rules
```
Then hard-refresh the leaderboard screen.

### Reset button doesn't work

This was the v3 bug we just fixed in v4. If it's still broken:
1. Open F12 → Console on the host's browser
2. Tap **New Game**, type a secret, tap **Start Round**
3. Look for any error messages in the console
4. Send me the console output

The v4 design uses a `round` counter (no subcollection deletes), so the old `transaction.get(collection)` compile error cannot recur.

---

## What to do next

After you complete Phase 6 (smoke test passes):

1. Reply with **"v1 shipped"** and your Vercel URL
2. I'll do a final review of the deployed app
3. We pick which Phase 2 feature to build first (Google sign-in is the easiest — ~1 hour of work; Race mode is the hardest — probably a full session)

If you get stuck at any step, send me:
- The exact command you ran
- The exact error message (copy-paste, no paraphrasing)
- Your `flutter --version` and `firebase --version` outputs

I'll get you unstuck in one reply.
