$ErrorActionPreference = 'Continue'

function L   { param($m,$c='Gray') Write-Host $m -ForegroundColor $c }
function OK  { param($m) L "  [+] $m" Green }
function WRN { param($m) L "  [!] $m" Yellow }

$CFLAGS = @(
  "disable-background-networking","disable-breakpad","disable-crash-reporter",
  "disable-logging","disable-domain-reliability","no-pings",
  "disable-background-timer-throttling","disable-component-update",
  "disable-default-apps","no-default-browser-check","no-first-run",
  "disable-speech-api","disable-sync","disable-client-side-phishing-detection",
  "disable-hang-monitor","disable-prompt-on-repost","disable-translate",
  "enable-gpu-rasterization","enable-zero-copy","ignore-gpu-blocklist",
  "enable-oop-rasterization","enable-raw-draw","enable-drdc","enable-vulkan",
  "use-angle=d3d11",
  "enable-hardware-overlays=single-fullscreen,single-on-top,underlay",
  "disk-cache-size=209715200","media-cache-size=104857600",
  "enable-quic","enable-tcp-fast-open",
  "js-flags=--max-old-space-size=4096 --turbofan",
  "process-per-site","renderer-process-limit=8"
)
$CENABLE  = "MemorySaver,MemorySaverMultistateSavings,ParallelDownloading,CanvasOopRasterization,EnableDrDc,RawDraw,DirectCompositionVideoOverlays,UseSkiaRenderer,AsyncDns,PartitionedCookies,SplitCacheByNetworkIsolationKey,StrictOriginIsolation,BackForwardCache,BlockInsecurePrivateNetworkRequests,ReduceUserAgentMinorVersion"
$CDISABLE = "Translate,MediaRouter,OptimizationHints,OptimizationHintsFetching,OptimizationTargetPrediction,InterestFeedContentSuggestions,DialMediaRouteProvider,AutofillServerCommunication,CertificateTransparencyComponentUpdater,PrivacySandboxSettings4,FlocIdComputedEventLogging,BackgroundFetch,BackgroundSync,Prerender2,PrerenderFallbackToPreconnect,GlobalMediaControls,TabHoverCardImages,NewTabPageContentSuggestions"

function Apply-LocalState {
  param([string]$Path,[string]$Name)
  if (-not (Test-Path $Path)) { WRN "$Name Local State not found - open it once first."; return }
  try {
    $json  = Get-Content $Path -Raw | ConvertFrom-Json
    if (-not $json.browser) {
      $json | Add-Member -NotePropertyName browser -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $flags = $CFLAGS + @("enable-features=$CENABLE","disable-features=$CDISABLE")
    $json.browser | Add-Member -NotePropertyName command_line_args -NotePropertyValue $flags -Force
    $json | ConvertTo-Json -Depth 20 | Set-Content $Path -Encoding UTF8 -Force
    OK "$Name flags written ($($flags.Count))"
  } catch { WRN "$Name Local State error: $($_.Exception.Message)" }
}

function Apply-Policy {
  param([string]$Vendor,[string]$Name)
  try {
    $rk = "HKLM:\SOFTWARE\Policies\$Vendor"
    New-Item $rk -Force | Out-Null
    $t = @{
      HardwareAccelerationModeEnabled=1; MetricsReportingEnabled=0; UserFeedbackAllowed=0
      FeedbackSurveysEnabled=0; SafeBrowsingExtendedReportingEnabled=0
      UrlKeyedAnonymizedDataCollectionEnabled=0; SpellCheckServiceEnabled=0
      BackgroundModeEnabled=0; ComponentUpdatesEnabled=0; DefaultBrowserSettingEnabled=0
      PromotionalTabsEnabled=0; PaymentMethodQueryEnabled=0
      PrivacySandboxAdMeasurementEnabled=0; PrivacySandboxAdTopicsEnabled=0
      PrivacySandboxSiteEnabledAdsEnabled=0; NetworkPredictionOptions=2
      SitePerProcess=1; DefaultPopupsSetting=2; DefaultGeolocationSetting=2
      DefaultNotificationsSetting=2
    }
    if ($Name -eq 'Edge') {
      $t['StartupBoostEnabled']=0; $t['EdgeShoppingAssistantEnabled']=0
      $t['PersonalizationReportingEnabled']=0; $t['ShowRecommendationsEnabled']=0
      $t['SpotlightExperiencesAndRecommendationsEnabled']=0
      $t['NewTabPageContentEnabled']=0; $t['NewTabPageBingChatEnabled']=0
      $t['HubsSidebarEnabled']=0; $t['DiagnosticData']=0; $t['BingAdsSuppression']=1
    }
    if ($Name -eq 'Brave') {
      $t['BraveRewardsDisabled']=1; $t['BraveWalletDisabled']=1
      $t['BraveVPNDisabled']=1; $t['BraveAIChatEnabled']=0
    }
    if ($Name -eq 'Chrome') {
      $t['ChromeVariationsEnabled']=0; $t['SyncDisabled']=1
      $t['BrowserSignin']=0; $t['SearchSuggestEnabled']=0
    }
    $t.GetEnumerator() | ForEach-Object { Set-ItemProperty $rk $_.Key $_.Value -Type DWord -Force }
    $n = $t.Count
    OK "$Name policy written ($n keys)"
  } catch { WRN "$Name policy error: $($_.Exception.Message)" }
}

$USERJS = @'
user_pref("gfx.webrender.all", true);
user_pref("gfx.webrender.compositor", true);
user_pref("gfx.webrender.compositor.force-enabled", true);
user_pref("layers.acceleration.force-enabled", true);
user_pref("layers.gpu-process.enabled", true);
user_pref("media.hardware-video-decoding.force-enabled", true);
user_pref("gfx.canvas.accelerated", true);
user_pref("gfx.canvas.accelerated.cache-items", 32768);
user_pref("gfx.canvas.accelerated.cache-size", 512);
user_pref("dom.ipc.processCount", 8);
user_pref("browser.tabs.unloadOnLowMemory", true);
user_pref("network.http.max-connections", 900);
user_pref("network.http.http3.enabled", true);
user_pref("network.ssl_tokens_cache_enabled", true);
user_pref("network.prefetch-next", false);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.predictor.enabled", false);
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("network.trr.mode", 2);
user_pref("network.trr.uri", "https://mozilla.cloudflare-dns.com/dns-query");
user_pref("browser.cache.disk.enable", true);
user_pref("browser.cache.disk.capacity", 524288);
user_pref("browser.cache.disk.smart_size.enabled", false);
user_pref("browser.cache.memory.enable", true);
user_pref("browser.cache.memory.capacity", 131072);
user_pref("browser.sessionstore.interval", 60000);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.aboutConfig.showWarning", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.server", "");
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("toolkit.telemetry.newProfilePing.enabled", false);
user_pref("toolkit.telemetry.shutdownPingSender.enabled", false);
user_pref("toolkit.telemetry.updatePing.enabled", false);
user_pref("toolkit.telemetry.bhrPing.enabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("app.normandy.enabled", false);
user_pref("app.normandy.api_url", "");
user_pref("browser.ping-centre.telemetry", false);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("browser.discovery.enabled", false);
user_pref("browser.urlbar.suggest.quicksuggest.sponsored", false);
user_pref("browser.urlbar.quicksuggest.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.safebrowsing.downloads.remote.enabled", false);
user_pref("dom.security.https_only_mode", true);
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.trackingprotection.socialtracking.enabled", true);
user_pref("privacy.trackingprotection.cryptomining.enabled", true);
user_pref("privacy.trackingprotection.fingerprinting.enabled", true);
user_pref("privacy.fingerprintingProtection", true);
user_pref("dom.battery.enabled", false);
user_pref("media.peerconnection.ice.no_host", true);
user_pref("webgl.enable-debug-renderer-info", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.warnOnQuit", false);
user_pref("full-screen-api.warning.timeout", 0);
user_pref("accessibility.force_disabled", 1);
user_pref("layout.css.dpi", 0);
'@

function Apply-Firefox {
  param([string]$ProfRoot,[string]$Name)
  $profiles = Get-ChildItem $ProfRoot -Directory -EA SilentlyContinue
  if (-not $profiles) { WRN "$Name no profiles - open it once first."; return }
  foreach ($p in $profiles) {
    $USERJS | Set-Content (Join-Path $p.FullName 'user.js') -Encoding UTF8 -Force
    OK "$Name user.js written"
  }
}

L "Browser Optimizer" Cyan
L ("-"*50) DarkGray

$browsers = [ordered]@{}
@(
  @{Name='Brave'; Exe='brave.exe'; Vendor='BraveSoftware\Brave'; LocalState="$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Local State"},
  @{Name='Chrome'; Exe='chrome.exe'; Vendor='Google\Chrome'; LocalState="$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"},
  @{Name='Edge'; Exe='msedge.exe'; Vendor='Microsoft\Edge'; LocalState="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"}
) | ForEach-Object {
  $b = $_; $found = $null
  foreach ($root in @("$env:ProgramFiles","$env:LOCALAPPDATA","${env:ProgramFiles(x86)}")) {
    $p = Get-ChildItem -Recurse -Filter $b.Exe -Path $root -EA SilentlyContinue | Select-Object -First 1
    if ($p) { $found = $p.FullName; break }
  }
  if (-not $found) {
    $reg = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$($b.Exe)" -EA SilentlyContinue).'(default)'
    if ($reg -and (Test-Path $reg)) { $found = $reg }
  }
  if ($found) { $b['ExePath'] = $found; $browsers[$b.Name] = $b }
}
@(
  @{Name='Firefox'; ProfRoot="$env:APPDATA\Mozilla\Firefox\Profiles"},
  @{Name='LibreWolf'; ProfRoot="$env:APPDATA\librewolf\Profiles"}
) | ForEach-Object { if (Test-Path $_.ProfRoot) { $browsers[$_.Name] = $_ } }

if ($browsers.Count -eq 0) { L "No browsers detected." Red; Read-Host "Enter to exit"; exit 1 }

L "`nDetected:" Cyan
$browsers.Keys | ForEach-Object { L "  - $_" White }

L "`nApplying..." Cyan
foreach ($name in $browsers.Keys) {
  $b = $browsers[$name]
  L "`n--- $name ---" White
  if ($b.ContainsKey('LocalState')) {
    Apply-LocalState $b.LocalState $name
    Apply-Policy $b.Vendor $name
  } else {
    Apply-Firefox $b.ProfRoot $name
  }
}

L "`nDone. Restart your browsers." Cyan

