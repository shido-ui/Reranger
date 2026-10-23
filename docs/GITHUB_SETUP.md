# RERANGER — GITHUB ACTIONS SETUP & APK RELEASE GUIDE

This guide provides exact, step-by-step instructions for the Product Owner on how to push the clean, isolated release candidate from `/root/reranger_release/` to GitHub, trigger the automated GitHub Actions CI/CD pipeline, and download the compiled Android release APKs.

---

## 1. Overview of the Release Package

The `/root/reranger_release/` directory is an isolated, push-ready release bundle that contains:
- Complete Flutter 3.47.7 application source code (`lib/`).
- Complete automated test suite (271 tests across `test/`).
- Native Android Gradle project configuration (`android/`).
- Preset asset catalogs and thumbnails (`assets/`).
- CI quality pipeline verification scripts (`scripts/verify.sh` and `scripts/audit_security_licenses.py`).
- GitHub Actions CI workflow (`.github/workflows/ci.yml`).
- Legal compliance, license attributions, and third-party notices (`THIRD_PARTY_NOTICES.md`).
- Hardware matrix, architectural specifications, and documentation (`docs/`).

All local build caches (`build/`, `.dart_tool/`, `.gradle/`, and native `.so`/`.apk` binaries) have been stripped to keep the Git push fast, clean, and lightweight.

---

## 2. Step 1: Initialize Git Repository in the Release Folder

Run the following commands in your terminal to initialize Git and commit the release files:

```bash
# Navigate to the isolated release directory
cd /root/reranger_release

# Initialize a new Git repository
git init -b main

# Configure Git user identity (if not already set globally)
git config user.name "Your Name"
git config user.email "your.email@example.com"

# Stage all files (respecting the strict .gitignore)
git add .

# Verify staged files (ensure build/ and .dart_tool/ are excluded)
git status

# Create the initial release candidate commit
git commit -m "chore(release): Reranger v1.0.0-rc1 release candidate with automated CI pipeline"
```

---

## 3. Step 2: Connect and Push to Your GitHub Repository

1. **Create a New Repository on GitHub**:
   - Go to [https://github.com/new](https://github.com/new).
   - Enter Repository Name: `reranger` (or your chosen repository name).
   - Visibility: Choose **Private** or **Public**.
   - **Important**: Do *not* initialize with a README, .gitignore, or license (these are already provided).
   - Click **Create repository**.

2. **Add Remote and Push**:
   Replace `YOUR_USERNAME` and `YOUR_REPOSITORY` with your actual GitHub credentials:

   ```bash
   # Add your GitHub remote repository URL
   git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git

   # Push to the main branch
   git push -u origin main
   ```

   > [!NOTE]
   > If using Personal Access Tokens (PAT) or SSH keys, ensure your token has `repo` and `workflow` scopes.

---

## 4. Step 3: Monitor GitHub Actions Cloud Build

Once the code is pushed to `main`, GitHub Actions automatically triggers the CI/CD pipeline defined in `.github/workflows/ci.yml`.

1. Open your repository on GitHub in a web browser:
   `https://github.com/YOUR_USERNAME/YOUR_REPOSITORY`
2. Click on the **Actions** tab in the top navigation bar.
3. You will see an active workflow run titled:
   **`Reranger Release Candidate & Automated APK Build Pipeline`** (triggered by your push).
4. Click on the workflow run to view the real-time execution steps:
   - **Step 1:** Checkout Code Repository (`actions/checkout@v4`).
   - **Step 2:** Set up Java 17 Toolchain (`actions/setup-java@v4`, distribution `zulu`, version `17`).
   - **Step 3:** Set up Flutter SDK (`subosito/flutter-action@v2`, version `3.47.7`).
   - **Step 4:** Resolve Dependencies (`flutter pub get`).
   - **Step 5:** Run Verification Pipeline (`bash scripts/verify.sh` — checks formatting, static analysis, licensing, and executes all 271 automated tests).
   - **Step 6:** Build Android Release APK (`flutter build apk --release --split-per-abi`).
   - **Step 7:** Upload Release APK Artifacts (`actions/upload-artifact@v4`).

> [!TIP]
> You can also manually trigger this workflow at any time by clicking **Actions** $\to$ **Reranger Release Candidate & Automated APK Build Pipeline** $\to$ **Run workflow** dropdown $\to$ **Run workflow**.

---

## 5. Step 4: Download the Compiled Release APKs

1. When the workflow finishes with a green checkmark (**Passed**):
2. Scroll down to the bottom of the workflow summary page to the **Artifacts** section.
3. You will find the downloadable artifact named:
   **`reranger-release-apk`**
4. Click on `reranger-release-apk` to download the zip bundle.
5. Extract the downloaded zip file. You will find the release-optimized APKs split by target ABI architecture:
   - `app-arm64-v8a-release.apk` (Recommended for modern 64-bit Android devices, including Google Pixel 8/9/10, Samsung Galaxy S23/S24).
   - `app-armeabi-v7a-release.apk` (For legacy 32-bit ARM devices).
   - `app-x86_64-release.apk` (For 64-bit emulators and Intel/AMD Chromebooks).

---

## 6. Verification Checklist for Product Owner

- [ ] All 271 unit, widget, preset, integration, and benchmark tests pass in the cloud runner.
- [ ] Static analysis reports `No issues found!`.
- [ ] License scan confirms 57 dependencies mapped with 0 unknown licenses.
- [ ] Android release APKs are produced and uploaded to GitHub Artifacts.
- [ ] Install `app-arm64-v8a-release.apk` on a physical device or emulator to confirm standalone launch and 100% offline functionality.
