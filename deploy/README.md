# Deploy Rituva on GCP — Cloud SQL (Postgres) + Cloud Run

The API is stateless; state lives in Postgres. Cloud Run runs the container and scales
to zero; Cloud SQL holds members/plans/intake. The LLM key lives in Secret Manager.

> **You** run these (I can't sign into your GCP account).
> **PowerShell note (Windows):** run each command **on one line** — PowerShell does NOT
> use `\` for line-continuation (that's bash). Every command below is already single-line.
> **Project ID vs name:** the ID is lowercase (e.g. `rituva`), not the display name.
> **Cost:** the smallest Cloud SQL (`db-f1-micro`) is ~$8–15/mo (always-on). Cloud Run is
> ~free at low traffic, but the project still needs **billing enabled** to use it.
> Prefer ~$0? See "Cheaper: free Postgres" at the bottom.

## 0. Project, billing, APIs
```
gcloud auth login
gcloud config set project rituva
gcloud config set run/region asia-south1
gcloud billing projects link rituva --billing-account=YOUR_BILLING_ACCOUNT_ID
gcloud services enable run.googleapis.com sqladmin.googleapis.com secretmanager.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com
```
(`gcloud billing accounts list` shows your billing account IDs.)

## 1. Cloud SQL (Postgres 16)
```
gcloud sql instances create rituva-db --database-version=POSTGRES_16 --tier=db-f1-micro --region=asia-south1
gcloud sql databases create rituva --instance=rituva-db
gcloud sql users set-password postgres --instance=rituva-db --password=CHOOSE_A_STRONG_PW
gcloud sql instances describe rituva-db --format="value(connectionName)"
```
The last line prints the **connection name** (e.g. `rituva:asia-south1:rituva-db`) — you'll
need it below. Instance creation takes ~5–10 min.

## 2. Store the LLM key as a secret
**PowerShell:**
```
Set-Content -NoNewline -Encoding ascii -Path key.txt -Value "nvapi-XXXXXXXX"; gcloud secrets create nvidia-api-key --data-file=key.txt; Remove-Item key.txt
```
**bash:**
```
printf 'nvapi-XXXXXXXX' | gcloud secrets create nvidia-api-key --data-file=-
```
(For Gemini use your AI Studio key and set `RITUVA_LLM_PROVIDER=gemini` in step 3.)

## 3. Deploy the API to Cloud Run (build from source)
Run from the **repo root** (where the `Dockerfile` is).
**PowerShell:**
```
$CONN = gcloud sql instances describe rituva-db --format="value(connectionName)"
gcloud run deploy rituva-api --source . --allow-unauthenticated --add-cloudsql-instances $CONN --set-secrets NVIDIA_API_KEY=nvidia-api-key:latest --set-env-vars "RITUVA_LLM_PROVIDER=nvidia,RITUVA_DB=postgresql://postgres:CHOOSE_A_STRONG_PW@/rituva?host=/cloudsql/$CONN"
```
**bash:** same, with `CONN=$(gcloud sql instances describe rituva-db --format='value(connectionName)')`.

`--source .` uses the `Dockerfile` (Cloud Build). The `host=/cloudsql/...` DSN reaches
Cloud SQL over the Unix socket that `--add-cloudsql-instances` mounts. On first boot the
app auto-creates its tables and seeds the demo members. (Use a password with no `@ : / ?`
characters, or URL-encode them, since it sits inside the DSN.)

## 4. Verify
```
gcloud run services describe rituva-api --format="value(status.url)"
```
Open `<that URL>/health` (should show `"llm":"nvidia"` + foods/recipes) and `<URL>/app/`.

## 5. Point the mobile app at it
- GitHub → repo **Settings → Secrets and variables → Actions → Variables** → add
  `RITUVA_API = https://rituva-api-....run.app`. The next APK/iOS build bakes it in.
- Or in the app: **Profile → Server** → paste the Cloud Run URL.

## Notes
- **IFCT data is NOT in this deployment** (gitignored + `.dockerignore`d) — the cloud
  product uses the base curated KB, compliant with IFCT's terms until NIN grants
  permission. See `docs/NIN-IFCT-permission-request.md`.
- Rotate the DB password / LLM key via Secret Manager; never commit them.
- Pause SQL billing when unused: `gcloud sql instances patch rituva-db --activation-policy=NEVER`.

## Cheaper: free Postgres (~$0) instead of Cloud SQL
Billing must still be enabled (Cloud Run requires it), but you can skip Cloud SQL:
1. Create a free Postgres at **neon.tech** (or supabase.com); copy its connection string.
2. Skip step 1 and the `--add-cloudsql-instances` flag; deploy with
   `--set-env-vars "RITUVA_LLM_PROVIDER=nvidia,RITUVA_DB=postgresql://USER:PW@HOST/db?sslmode=require"`.
Cloud Run's free tier + Neon's free tier keeps real cost near $0.
