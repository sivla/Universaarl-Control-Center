[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$env:GIT_OPTIONAL_LOCKS = '0'

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$portfolioPath = Join-Path $root 'portfolio.state.json'
$portfolio = Get-Content -LiteralPath $portfolioPath -Raw | ConvertFrom-Json
if ($portfolio.schemaVersion -ne 1 -or @($portfolio.projects).Count -ne 3) { throw 'Der schlanke Portfoliozustand fehlt oder ist unvollstaendig.' }
$expectedPortfolioFields = @('projectId','overallGoal','largestGap','lastCommit','mainBlocker','nextDeliveryBlock')
$expectedProjectIds = @('spectra','blueprint','project-twin')
foreach ($project in @($portfolio.projects)) {
    $actualFields = @($project.PSObject.Properties.Name)
    if ($actualFields.Count -ne $expectedPortfolioFields.Count -or @($expectedPortfolioFields | Where-Object { $_ -notin $actualFields }).Count -gt 0) { throw "Portfolioeintrag '$($project.projectId)' ist nicht lean oder unvollstaendig." }
    if ($project.projectId -notin $expectedProjectIds -or $project.lastCommit -notmatch '^[0-9a-f]{40}$') { throw 'Portfolioeintrag besitzt keine erlaubte Projektkennung oder volle Commit-SHA.' }
    foreach ($field in @('overallGoal','largestGap','mainBlocker','nextDeliveryBlock')) {
        if ([string]::IsNullOrWhiteSpace([string]$project.$field)) { throw "Portfoliofeld '$field' ist leer." }
    }
}
if (@($portfolio.projects.projectId | Select-Object -Unique).Count -ne 3) { throw 'Portfolio enthaelt doppelte Projektkennungen.' }
$forbidden = @(
    'consumer',
    'scripts\Install-BCProjectOSConsumer.ps1',
    'scripts\Test-BCProjectOSConsumer.ps1',
    'tests\Test-BCProjectOSConsumer.ps1'
)

foreach ($relative in $forbidden) {
    $path = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $path.StartsWith($root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Ungueltiger Rollenpruefpfad: $relative"
    }
    if (Test-Path -LiteralPath $path) {
        throw "Das Kontrollzentrum enthaelt einen verbotenen BCProjectOS-Consumer-/Installationspfad: $relative"
    }
}

$tracked = @(& git -C $root --no-optional-locks ls-files)
if ($LASTEXITCODE -ne 0) { throw 'Versionierte Dateiliste konnte nicht gelesen werden.' }
foreach ($relative in $forbidden) {
    $normalized = $relative -replace '\\','/'
    if (@($tracked | Where-Object { $_ -eq $normalized -or $_.StartsWith($normalized.TrimEnd('/') + '/', [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
        throw "Verbotener Consumer-/Installationspfad ist versioniert: $relative"
    }
}

$config = Get-Content -LiteralPath (Join-Path $root 'monitor.config.json') -Raw | ConvertFrom-Json
. (Join-Path $root 'scripts\Universaarl-Control.Common.ps1')
Assert-UniversaarlMonitorConfiguration -Configuration $config
$ids = @($config.projects | ForEach-Object { [string]$_.id })
if ($ids.Count -ne 2 -or $ids -cnotcontains 'blueprint' -or $ids -cnotcontains 'project-twin') {
    throw 'Das Kontrollzentrum muss genau Blueprint und Project Twin als operative Zielprojekte behalten.'
}
$verificationSourceNames = @($config.verificationSources.PSObject.Properties | ForEach-Object { [string]$_.Name })
if ($verificationSourceNames.Count -ne 1 -or $verificationSourceNames[0] -cne 'bcprojectos' -or
    $config.verificationSources.bcprojectos.verificationOnly -isnot [bool] -or -not $config.verificationSources.bcprojectos.verificationOnly -or
    @($config.verificationSources.bcprojectos.PSObject.Properties | Where-Object { $_.Name -ceq 'publish' }).Count -ne 0) {
    throw 'BCProjectOS muss genau eine reine Verifikationsquelle ohne Publisherrechte bleiben.'
}
$relationshipIds = @($config.relationships | ForEach-Object { [string]$_.id })
if ($relationshipIds.Count -ne 2 -or @($relationshipIds | Sort-Object -Unique).Count -ne 2 -or
    $relationshipIds -cnotcontains 'blueprint-binds-spectra' -or $relationshipIds -cnotcontains 'twin-reads-blueprint') {
    throw 'Die Rollengrenze erfordert exakt die Spectra-Bindungs- und portable Snapshot-Lesebeziehung.'
}

$agents = Get-Content -LiteralPath (Join-Path $root 'AGENTS.md') -Raw
if ($agents -notmatch 'installiert BCProjectOS nicht' -or $agents -notmatch 'read-only Release-Evidence-Quelle') {
    throw 'Die Kontrollzentrum-Rollengrenze ist in AGENTS.md nicht eindeutig verankert.'
}

Write-Output 'Kontrollzentrum-Rollengrenze bestanden: kein Consumer, kein Installationspfad, genau zwei operative Zielprojekte und BCProjectOS nur als Spectra-Verifikationsquelle.'
