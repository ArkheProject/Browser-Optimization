<# :
@echo off
fltmc >nul 2>&1 || (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((Get-Content -Raw -LiteralPath '%~f0')))"
exit /b %errorlevel%
: #>

$ErrorActionPreference = 'Continue'
function L($m, $c='Gray') { Write-Host $m -ForegroundColor $c }
function OK($m)  { L "  [+] $m" Green }
function WRN($m) { L "  [!] $m" Yellow }

L "Browser Optimizer — registry + flags + user.js, no shortcuts" Cyan
L ("-"*55) DarkGray

# ---------------------------------------------------------------------------
# AUTO-DETECT installed browsers
# ---------------------------------------------------------------------------
$browsers = [ordered]@{}

$chromiumCandidates = @(
  @{ Name='Brave';  Exe='brave.exe';  Vendor='BraveSoftware\Brave';
     LocalState="$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Local State" },
  @{ Name='Chrome'; Exe='chrome.exe'; Vendor='Google\Chrome';
     LocalState="$env:LOCALAPPDATA\Google\Chrome\User Data\Local State" },
  @{ Name='Edge';   Exe='msedge.exe'; Vendor='Microsoft\Edge';
     LocalState="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State" }
)

foreach ($b in $chromiumCandidates) {
  $found = $null
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

$firefoxCandidates = @(
  @{ Name='Firefox';   Exe='firefox.exe';   ProfRoot="$env:APPDATA\Mozilla\Firefox\Profiles" },
  @{ Name='LibreWolf'; Exe='librewolf.exe'; ProfRoot="$env:APPDATA\librewolf\Profiles" }
)
foreach ($b in $firefoxCandidates) {
  if (Test-Path $b.ProfRoot) { $browsers[$b.Name] = $b }
}

if ($browsers.Count -eq 0) {
  L "No supported browsers detected." Red
  Read-Host "Enter to exit"; exit 1
}

L "`nDetected browsers:" Cyan
foreach ($name in $browsers.Keys) { L "  - $name" White }
L ""

# ---------------------------------------------------------------------------
# CHROMIUM: Local State flags (applied every launch, no shortcut needed)
# ---------------------------------------------------------------------------

# Flags that disable background/telemetry/bloat processes
$chromiumFlags = @(
  # Telemetry / crash reporting
  "disable-background-networking",
  "disable-breakpad",
  "disable-crash-reporter",
  "disable-logging",
  "disable-domain-reliability",
  "no-pings",

  # Bloat features
  "disable-background-timer-throttling",
  "disable-component-update",
  "disable-default-apps",
  "no-default-browser-check",
  "no-first-run",
  "disable-speech-api",
  "disable-sync",                        # no Google/Brave account sync overhead
  "disable-notifications",               # no permission spam on startup
  "disable-client-side-phishing-detection", # sends hashes to Google
  "disable-hang-monitor",
  "disable-prompt-on-repost",
  "disable-translate",

  # GPU / rendering performance
  "enable-gpu-rasterization",
  "enable-zero-copy",
  "ignore-gpu-blocklist",
  "enable-oop-rasterization",            # GPU raster in separate process
  "enable-raw-draw",                     # skip intermediate surface compositing
  "enable-drdc",                         # Display compositor runs on GPU thread
  "enable-vulkan",                       # Vulkan backend where supported
  "use-angle=d3d11",                     # D3D11 ANGLE for best Windows GPU path
  "enable-hardware-overlays=single-fullscreen,single-on-top,underlay",

  # Network / cache
  "disk-cache-size=209715200",           # 200 MB disk cache (default is tiny)
  "media-cache-size=104857600",          # 100 MB media cache
  "enable-quic",                         # HTTP/3 QUIC where available
  "enable-tcp-fast-open",

  # V8 / JS performance
  "js-flags=--max-old-space-size=4096 --optimize-for-size=0 --turbofan",

  # Process model
  "process-per-site",                    # fewer renderer processes vs per-tab
  "renderer-process-limit=8"             # cap runaway tab processes
)

$chromiumEnableFeatures = @(
  # Memory
  "MemorySaver",                         # discard background tabs
  "MemorySaverMultistateSavings",
  "SmartCardWebAPI",

  # Rendering
  "ParallelDownloading",
  "CanvasOopRasterization",
  "EnableDrDc",
  "RawDraw",
  "DirectCompositionVideoOverlays",
  "UseSkiaRenderer",
  "OverlayScrollbar",

  # Network
  "AsyncDns",                            # async DNS resolver
  "PartitionedCookies",                  # privacy: isolate cookies per site
  "SplitCacheByNetworkIsolationKey",     # privacy: isolate HTTP cache per site
  "StrictOriginIsolation",               # stronger site isolation

  # UI responsiveness
  "ThrottleDisplayNoneAndVisibilityHiddenCrossOriginIframes",
  "BackForwardCache",                    # instant back/forward navigation

  # Security
  "BlockInsecurePrivateNetworkRequests",
  "ReduceUserAgentMinorVersion",         # reduces fingerprinting surface
  "EnableCsrssLockdown"
)

$chromiumDisableFeatures = @(
  # Privacy/telemetry
  "Translate",
  "MediaRouter",
  "OptimizationHints",
  "OptimizationHintsFetching",
  "OptimizationHintsFieldTrials",
  "OptimizationTargetPrediction",
  "InterestFeedContentSuggestions",
  "DialMediaRouteProvider",
  "AutofillServerCommunication",
  "CertificateTransparencyComponentUpdater",
  "PrivacySandboxSettings4",             # Google Privacy Sandbox / Topics API
  "FlocIdComputedEventLogging",
  "SignedExchangeSubresourcePrefetch",
  "SubresourceWebBundles",
  "CrossSiteDocumentBlockingIfIsolating",

  # Background / startup overhead
  "BackgroundFetch",
  "BackgroundSync",
  "Prerender2",                          # prerender uses CPU/RAM speculatively
  "PrerenderFallbackToPreconnect",
  "HttpsUpgrades",                       # let the user decide, not the browser

  # UI/UX bloat
  "GlobalMediaControls",                 # removes media overlay from toolbar
  "TabHoverCardImages",                  # no image previews on hover
  "NewTabPageContentSuggestions"
)

function Apply-ChromiumLocalState($localStatePath, $browserName) {
  if (-not (Test-Path $localStatePath)) {
    WRN "$browserName Local State not found — launch it once first."
    return
  }
  try {
    $raw = Get-Content $localStatePath -Raw
    $json = $raw | ConvertFrom-Json
    if (-not $json.browser) {
      $json | Add-Member -NotePropertyName browser -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $allFlags = $chromiumFlags + @(
      "enable-features=$($chromiumEnableFeatures -join ',')",
      "disable-features=$($chromiumDisableFeatures -join ',')"
    )
    $json.browser | Add-Member -NotePropertyName 'command_line_args' `
      -NotePropertyValue $allFlags -Force
    $json | ConvertTo-Json -Depth 20 | Set-Content $localStatePath -Encoding UTF8 -Force
    OK "$browserName Local State updated ($($allFlags.Count) flags)"
  } catch {
    WRN "$browserName Local State write failed: $($_.Exception.Message)"
  }
}

# ---------------------------------------------------------------------------
# CHROMIUM: Policy registry tweaks (HKLM — needs admin, enforced by OS)
# ---------------------------------------------------------------------------
function Apply-ChromiumPolicy($vendor, $browserName) {
  $rk = "HKLM:\SOFTWARE\Policies\$vendor"
  New-Item $rk -Force | Out-Null

  # --- Common Chromium policy ---
  $tweaks = @{
    # Performance
    HardwareAccelerationModeEnabled          = 1
    RendererCodeIntegrityEnabled             = 0  # slight perf hit on older CPUs

    # Privacy / telemetry
    MetricsReportingEnabled                  = 0
    UserFeedbackAllowed                      = 0
    FeedbackSurveysEnabled                   = 0
    SafeBrowsingExtendedReportingEnabled     = 0
    UrlKeyedAnonymizedDataCollectionEnabled  = 0
    SpellCheckServiceEnabled                 = 0  # no text sent to remote spellcheck

    # Background / startup overhead
    BackgroundModeEnabled                    = 0
    ComponentUpdatesEnabled                  = 0
    DefaultBrowserSettingEnabled             = 0
    PromotionalTabsEnabled                   = 0
    PaymentMethodQueryEnabled                = 0

    # Privacy sandbox / ads
    PrivacySandboxAdMeasurementEnabled       = 0
    PrivacySandboxAdTopicsEnabled            = 0
    PrivacySandboxSiteEnabledAdsEnabled      = 0

    # Network
    DnsOverHttpsMode                         = 1  # prefer DoH (secure)
    NetworkPredictionOptions                 = 2  # disable prefetch/preconnect

    # Security
    SitePerProcess                           = 1
    InsecureContentAllowedForUrls            = 0
    DefaultPopupsSetting                     = 2  # block popups by default
    DefaultGeolocationSetting                = 2  # block geolocation by default
    DefaultNotificationsSetting              = 2  # block notifications by default
  }

  # --- Edge-specific ---
  if ($browserName -eq 'Edge') {
    $tweaks['StartupBoostEnabled']                           = 0
    $tweaks['EdgeShoppingAssistantEnabled']                  = 0
    $tweaks['EdgeCollectionsEnabled']                        = 0
    $tweaks['PersonalizationReportingEnabled']               = 0
    $tweaks['ShowRecommendationsEnabled']                    = 0
    $tweaks['SpotlightExperiencesAndRecommendationsEnabled'] = 0
    $tweaks['NewTabPageContentEnabled']                      = 0
    $tweaks['NewTabPageBingChatEnabled']                     = 0
    $tweaks['HubsSidebarEnabled']                           = 0
    $tweaks['EdgeFollowEnabled']                             = 0
    $tweaks['EdgeOpenInSidebarEnabled']                      = 0
    $tweaks['DiagnosticData']                                = 0
    $tweaks['SendSiteInfoToImproveServices']                 = 0
    $tweaks['AddressBarMicrosoftSearchInBingProviderEnabled']= 0
    $tweaks['CryptoWalletEnabled']                           = 0
    $tweaks['BingAdsSuppression']                            = 1
    $tweaks['SmartActionsBlockList']                         = 3  # disable all smart actions
  }

  # --- Brave-specific ---
  if ($browserName -eq 'Brave') {
    $tweaks['BraveRewardsDisabled'] = 1
    $tweaks['BraveWalletDisabled']  = 1
    $tweaks['BraveVPNDisabled']     = 1
    $tweaks['BraveAIChatEnabled']   = 0
  }

  # --- Chrome-specific ---
  if ($browserName -eq 'Chrome') {
    $tweaks['ChromeVariationsEnabled']         = 0  # A/B experiments off
    $tweaks['SyncDisabled']                    = 1
    $tweaks['BrowserSignin']                   = 0  # no forced Google sign-in prompt
    $tweaks['CloudPrintSubmitEnabled']         = 0
    $tweaks['PrintingEnabled']                 = 1  # keep printing, just disable cloud
    $tweaks['SearchSuggestEnabled']            = 0  # stops keystrokes being sent to Google
  }

  foreach ($kv in $tweaks.GetEnumerator()) {
    Set-ItemProperty $rk $kv.Key $kv.Value -Type DWord -Force
  }
  OK "$browserName policy keys written ($($tweaks.Count) keys)"
}

# ---------------------------------------------------------------------------
# FIREFOX / LIBREWOLF: user.js
# ---------------------------------------------------------------------------
$firefoxUserJs = @"
// Browser Optimizer — performance + privacy, no breakage

// --- GPU / Rendering ---
user_pref("gfx.webrender.all", true);
user_pref("gfx.webrender.compositor", true);
user_pref("gfx.webrender.compositor.force-enabled", true);
user_pref("gfx.webrender.program-binary-disk", true);
user_pref("layers.acceleration.force-enabled", true);
user_pref("layers.gpu-process.enabled", true);
user_pref("media.hardware-video-decoding.force-enabled", true);
user_pref("media.hardware-video-decoding.enabled", true);
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("gfx.canvas.accelerated", true);
user_pref("gfx.canvas.accelerated.cache-items", 32768);
user_pref("gfx.canvas.accelerated.cache-size", 512);
user_pref("gfx.content.skia-font-cache-size", 80);

// --- Process / Memory ---
user_pref("dom.ipc.processCount", 8);
user_pref("dom.ipc.processCount.webIsolated", 4);
user_pref("browser.tabs.unloadOnLowMemory", true);
user_pref("browser.low_commit_space_threshold_mb", 500);
user_pref("javascript.options.mem.high_water_mark", 128);
user_pref("javascript.options.mem.gc_high_frequency_heap_growth_max", 3);
user_pref("javascript.options.mem.gc_high_frequency_high_limit_mb", 500);
user_pref("javascript.options.mem.gc_high_frequency_low_limit_mb", 100);
user_pref("javascript.options.mem.gc_low_frequency_heap_growth", 1.15);
user_pref("javascript.options.mem.gc_max_empty_chunk_count", 30);
user_pref("javascript.options.mem.gc_min_empty_chunk_count", 1);
user_pref("javascript.options.mem.gc_allocation_threshold_mb", 30);

// --- Network / Speed ---
user_pref("network.http.max-connections", 900);
user_pref("network.http.max-persistent-connections-per-server", 10);
user_pref("network.http.max-persistent-connections-per-proxy", 48);
user_pref("network.http.pipelining", true);
user_pref("network.http.pipelining.maxrequests", 8);
user_pref("network.http.http3.enabled", true);
user_pref("network.ssl_tokens_cache_enabled", true);
user_pref("network.ssl_tokens_cache_capacity", 10240);
user_pref("network.prefetch-next", false);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.predictor.enabled", false);
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("network.early-hints.enabled", true);
user_pref("network.trr.mode", 2);                // DoH preferred
user_pref("network.trr.uri", "https://mozilla.cloudflare-dns.com/dns-query");

// --- Cache ---
user_pref("browser.cache.disk.enable", true);
user_pref("browser.cache.disk.capacity", 524288);  // 512 MB
user_pref("browser.cache.disk.smart_size.enabled", false);
user_pref("browser.cache.memory.enable", true);
user_pref("browser.cache.memory.capacity", 131072); // 128 MB
user_pref("browser.cache.offline.enable", false);

// --- Session / Startup ---
user_pref("browser.sessionstore.interval", 60000);
user_pref("browser.sessionstore.max_tabs_undo", 5);
user_pref("browser.sessionstore.max_windows_undo", 1);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.page", 3);             // restore session
user_pref("browser.aboutConfig.showWarning", false);
user_pref("reader.parse-on-load.enabled", false);

// --- Privacy / Telemetry ---
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.server", "");
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("toolkit.telemetry.newProfilePing.enabled", false);
user_pref("toolkit.telemetry.shutdownPingSender.enabled", false);
user_pref("toolkit.telemetry.updatePing.enabled", false);
user_pref("toolkit.telemetry.bhrPing.enabled", false);
user_pref("toolkit.telemetry.firstShutdownPing.enabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("app.normandy.enabled", false);
user_pref("app.normandy.api_url", "");
user_pref("browser.ping-centre.telemetry", false);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry.ut.events", false);
user_pref("browser.newtabpage.activity-stream.feeds.discoverystreamfeed", false);
user_pref("browser.newtabpage.activity-stream.feeds.snippets", false);
user_pref("browser.discovery.enabled", false);
user_pref("browser.urlbar.suggest.quicksuggest.sponsored", false);
user_pref("browser.urlbar.suggest.quicksuggest.nonsponsored", false);
user_pref("browser.urlbar.quicksuggest.enabled", false);
user_pref("browser.urlbar.trending.featureGate", false);
user_pref("browser.urlbar.suggest.trending", false);
user_pref("extensions.pocket.enabled", false);
user_pref("extensions.getAddons.showPane", false);
user_pref("extensions.htmlaboutaddons.recommendations.enabled", false);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.safebrowsing.malware.enabled", true);   // keep malware check
user_pref("browser.safebrowsing.phishing.enabled", true);  // keep phishing check
user_pref("browser.safebrowsing.provider.google4.updateURL", ""); // stop sending data
user_pref("browser.safebrowsing.provider.google4.reportURL", "");
user_pref("browser.safebrowsing.downloads.remote.enabled", false);

// --- Security ---
user_pref("dom.security.https_only_mode", true);
user_pref("dom.security.https_only_mode_ever_enabled", true);
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.trackingprotection.socialtracking.enabled", true);
user_pref("privacy.trackingprotection.cryptomining.enabled", true);
user_pref("privacy.trackingprotection.fingerprinting.enabled", true);
user_pref("privacy.fingerprintingProtection", true);
user_pref("privacy.resistFingerprinting.autoDeclineNoUserInputCanvasPrompts", true);
user_pref("dom.battery.enabled", false);           // hide battery API (fingerprint)
user_pref("dom.vibrator.enabled", false);
user_pref("media.peerconnection.ice.no_host", true); // WebRTC local IP leak fix
user_pref("webgl.disabled", false);                // keep WebGL (games/apps need it)
user_pref("webgl.enable-debug-renderer-info", false); // hide GPU vendor from JS

// --- UI / Behavior ---
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.tabs.warnOnCloseOtherTabs", false);
user_pref("browser.warnOnQuit", false);
user_pref("full-screen-api.warning.timeout", 0);
user_pref("accessibility.force_disabled", 1);      // accessibility hooks add overhead
user_pref("layout.css.dpi", 0);
user_pref("ui.prefersReducedMotion", 1);
"@

function Apply-Firefox($profRoot, $browserName) {
  $profiles = Get-ChildItem $profRoot -Directory -EA SilentlyContinue
  if (-not $profiles) {
    WRN "$browserName no profiles found — launch it once first."
    return
  }
  foreach ($p in $profiles) {
    $firefoxUserJs | Set-Content (Join-Path $p.FullName 'user.js') -Encoding UTF8 -Force
    OK "$browserName user.js → $($p.Name)"
  }
}

# ---------------------------------------------------------------------------
# APPLY TO ALL DETECTED
# ---------------------------------------------------------------------------
L "`nApplying tweaks..." Cyan

foreach ($name in $browsers.Keys) {
  $b = $browsers[$name]
  L "`n--- $name ---" White
  if ($b.ContainsKey('LocalState')) {
    Apply-ChromiumLocalState $b.LocalState $name
    Apply-ChromiumPolicy $b.Vendor $name
  } else {
    Apply-Firefox $b.ProfRoot $name
  }
}

L "`nDone. Restart your browsers for all changes to take effect." Cyan
L "Chromium: verify flags at chrome://version  (Command Line section)" Gray
L "Firefox:  verify at about:config" Gray
Read-Host "`nPress Enter to exit"
