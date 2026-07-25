# Deploy Rituva on GCP — Cloud SQL (Postgres) + Cloud Run

The API is stateless; state lives in Postgres. Cloud Run runs the container and scales
to zero; Cloud SQL holds members/plans/intake. The NVIDIA key lives in Secret Manager.

> You run these (I can't sign into your GCP account). Replace `PROJECT_ID` and pick a
> region (Mumbai = `asia-south1`). Cost: the smallest Cloud SQL (`db-f1-micro`) is
> ~₹700–1500/mo; Cloud Run is ~free at low traffic. Stop the SQL instance when unused.

## 0. Prerequisites
```bash
gcloud auth login
gcloud config set project PROJECT_ID
gcloud config set run/region asia-south1
gcloud services enable run.googleapis.com sqladmin.googleapis.com \
    secretmanager.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com
```

## 1. Cloud SQL (Postgres 16)
```bash
gcloud sql instances create rituva-db \
    --database-version=POSTGRES_16 --tier=db-f1-micro --region=asia-south1
gcloud sql databases create rituva --instance=rituva-db
gcloud sql users set-password postgres --instance=rituva-db --password='CHOOSE_A_STRONG_PW'
# note the connection name, e.g. PROJECT_ID:asia-south1:rituva-db
gcloud sql instances describe rituva-db --format='value(connectionName)'
```

## 2. Store the NVIDIA key as a secret
```bash
printf 'nvapi-XXXXXXXX' | gcloud secrets create nvidia-api-key --data-file=-
```

## 3. Deploy the API to Cloud Run (build from source)
```bash
CONN=$(gcloud sql instances describe rituva-db --format='value(connectionName)')
gcloud run deploy rituva-api \
    --source . \
    --allow-unauthenticated \
    --add-cloudsql-instances "$CONN" \
    --set-secrets NVIDIA_API_KEY=nvidia-api-key:latest \
    --set-env-vars "RITUVA_LLM_PROVIDER=nvidia,RITUVA_DB=postgresql://postgres:CHOOSE_A_STRONG_PW@/rituva?host=/cloudsql/$CONN"
```
`--source .` uses the `Dockerfile` (Cloud Build). The `host=/cloudsql/...` DSN reaches
Cloud SQL over the Unix socket that `--add-cloudsql-instances` mounts. On first boot the
app auto-creates its tables and seeds the demo members.

## 4. Verify
```bash
URL=$(gcloud run services describe rituva-api --format='value(status.url)')
curl -s "$URL/health"          # {"status":"ok",...,"llm":"nvidia"}
open "$URL/app/"               # the PWA, live on Postgres + NVIDIA
```

## 5. Point the mobile app at it
- GitHub → repo **Settings → Secrets and variables → Actions → Variables** → add
  `RITUVA_API = https://rituva-api-....run.app`. The next APK/iOS build bakes it in.
- Or in the app: **Profile → Server** → paste the Cloud Run URL.

## Notes
- **IFCT data is NOT in this deployment** (gitignored + `.dockerignore`d) — the cloud
  product uses the base curated KB, compliant with IFCT's terms until NIN grants
  permission. See `docs/NIN-IFCT-permission-request.md`.
- Rotate the DB password and NVIDIA key via Secret Manager; never commit them.
- To pause billing: `gcloud sql instances patch rituva-db --activation-policy=NEVER`.
