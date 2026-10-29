$ErrorActionPreference = 'Stop'
$containerName = 'ro-supabase-staging-local-test'
$localUrl = 'postgresql://postgres@127.0.0.1:55432/postgres'

$existing = docker ps -a --filter "name=^/$containerName$" --format '{{.Names}}'
if ($existing -contains $containerName) {
  throw "Refusing to reuse existing container '$containerName'. Inspect it manually first."
}

$containerId = docker run --rm --name $containerName `
  -e POSTGRES_HOST_AUTH_METHOD=trust `
  --tmpfs /var/lib/postgresql/data:rw,size=1g `
  -p 127.0.0.1:55432:5432 -d postgres:15-alpine
if ($LASTEXITCODE -ne 0 -or -not $containerId) {
  throw 'Could not start the disposable local PostgreSQL test container.'
}

try {
  $ready = $false
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    docker exec $containerId pg_isready -U postgres -d postgres *> $null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Milliseconds 500
  }
  if (-not $ready) { throw 'The disposable PostgreSQL test server did not become ready.' }

  $env:SUPABASE_LOCAL_TEST_URL = $localUrl
  node --test test/supabase_staging_postgres_test.cjs
  if ($LASTEXITCODE -ne 0) { throw 'Local PostgreSQL migration tests failed.' }
} finally {
  Remove-Item Env:SUPABASE_LOCAL_TEST_URL -ErrorAction SilentlyContinue
  docker stop $containerId *> $null
}
