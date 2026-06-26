// ═══════════════════════════════════════════════════════════════════════════
//  TikoHD — forces TikTok (iOS) to publish in true 1080p60 HD.
//
//  Layer 1  (PROVEN — exact BHTikTok-PLUS mechanism, raulsaeed/BHTikTokPlusPlus):
//           hook ACCCreationPublishAction and force is_open_hd / is_have_hd = YES
//           so the post is flagged HD-eligible and TikTok's own pipeline takes the
//           premium (bytevc1 1080p60) ingest branch instead of the 540p down-ladder.
//
//  Layer 2  (OUR IMPROVEMENT — off by default, opt-in): when TikTok's gallery/import
//           path asks AVAssetExportSession for a 540p/low preset, substitute the
//           HEVC-highest preset so an imported master is never downscaled on-device.
//
//  UX       A Tiko-styled in-app panel (two-finger hold ~0.8s) toggles both layers,
//           and a throttled toast confirms when HD is forced — BHTikTok is silent.
//
//  Build:   GitHub Actions (see .github/workflows/build.yml) → dylib → inject into a
//           stock TikTok IPA with pyzule/azule (see README.md). No Mac required.
// ═══════════════════════════════════════════════════════════════════════════

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#pragma mark - Preferences

static BOOL TikoBool(NSString *k, BOOL def) {
    id v = [NSUserDefaults.standardUserDefaults objectForKey:k];
    return v == nil ? def : [v boolValue];
}
static void TikoSetBool(NSString *k, BOOL v) {
    [NSUserDefaults.standardUserDefaults setBool:v forKey:k];
}
#define HD_ON       TikoBool(@"upload_hd", YES)            // Layer 1 — proven, default ON
#define PRESET_ON   TikoBool(@"tikohd_force_preset", NO)   // Layer 2 — beta, default OFF

static UIColor *TikoCyan(void) { return [UIColor colorWithRed:0.145 green:0.957 blue:0.933 alpha:1.0]; }

#pragma mark - Helpers

static UIWindow *TikoKeyWindow(void) {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class]) {
            for (UIWindow *w in ((UIWindowScene *)s).windows) { if (w.isKeyWindow) return w; }
        }
    }
    for (UIWindow *w in UIApplication.sharedApplication.windows) { if (w.isKeyWindow) return w; }
    return UIApplication.sharedApplication.windows.firstObject;
}

static NSTimeInterval _tikoLastToast = 0;
static void TikoToast(NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        if (now - _tikoLastToast < 3.0) return;   // throttle
        _tikoLastToast = now;
        UIWindow *win = TikoKeyWindow();
        if (!win) return;
        UILabel *l = [UILabel new];
        l.text = msg;
        l.font = [UIFont boldSystemFontOfSize:13];
        l.textColor = [UIColor colorWithRed:0.02 green:0.07 blue:0.10 alpha:1.0];
        l.backgroundColor = TikoCyan();
        l.textAlignment = NSTextAlignmentCenter;
        l.layer.cornerRadius = 10; l.clipsToBounds = YES;
        CGFloat w = 230, h = 36;
        CGFloat top = win.safeAreaInsets.top > 0 ? win.safeAreaInsets.top : 24;
        l.frame = CGRectMake((win.bounds.size.width - w) / 2, top + 10, w, h);
        l.alpha = 0; l.transform = CGAffineTransformMakeTranslation(0, -8);
        [win addSubview:l];
        [UIView animateWithDuration:0.25 animations:^{
            l.alpha = 1; l.transform = CGAffineTransformIdentity;
        } completion:^(BOOL _) {
            [UIView animateWithDuration:0.3 delay:1.5 options:0 animations:^{ l.alpha = 0; }
                             completion:^(BOOL __) { [l removeFromSuperview]; }];
        }];
    });
}

#pragma mark - Settings panel (Tiko-styled)

@interface TikoHDPanel : UIView
@end
@implementation TikoHDPanel

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(bgTap:)]];

        CGFloat cw = 304, ch = 214;
        UIView *card = [[UIView alloc] initWithFrame:CGRectMake((f.size.width - cw) / 2, (f.size.height - ch) / 2, cw, ch)];
        card.tag = 0x71D1;
        card.backgroundColor = [UIColor colorWithRed:0.07 green:0.075 blue:0.10 alpha:1.0];
        card.layer.cornerRadius = 18;
        card.layer.borderWidth = 1;
        card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor;
        card.layer.shadowColor = TikoCyan().CGColor;
        card.layer.shadowOpacity = 0.35; card.layer.shadowRadius = 22; card.layer.shadowOffset = CGSizeZero;
        [self addSubview:card];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 18, cw - 40, 24)];
        title.text = @"⚡ TikoHD"; title.font = [UIFont boldSystemFontOfSize:18]; title.textColor = UIColor.whiteColor;
        [card addSubview:title];

        UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(20, 43, cw - 40, 18)];
        sub.text = @"Force true 1080p60 on upload"; sub.font = [UIFont systemFontOfSize:12];
        sub.textColor = [UIColor colorWithWhite:1 alpha:0.5];
        [card addSubview:sub];

        [self rowIn:card y:80 label:@"Force HD flag" on:HD_ON sel:@selector(hdChanged:)];
        [self rowIn:card y:128 label:@"Force HD export (beta)" on:PRESET_ON sel:@selector(presetChanged:)];

        UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(16, ch - 30, cw - 32, 16)];
        hint.text = @"Two-finger hold to reopen · tap outside to close";
        hint.font = [UIFont systemFontOfSize:10]; hint.textColor = [UIColor colorWithWhite:1 alpha:0.35];
        hint.textAlignment = NSTextAlignmentCenter;
        [card addSubview:hint];

        card.alpha = 0; card.transform = CGAffineTransformMakeScale(0.92, 0.92);
        [UIView animateWithDuration:0.22 animations:^{ card.alpha = 1; card.transform = CGAffineTransformIdentity; }];
    }
    return self;
}

- (void)rowIn:(UIView *)card y:(CGFloat)y label:(NSString *)text on:(BOOL)on sel:(SEL)sel {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 200, 31)];
    l.text = text; l.font = [UIFont systemFontOfSize:14]; l.textColor = UIColor.whiteColor;
    [card addSubview:l];
    UISwitch *sw = [UISwitch new];
    sw.onTintColor = TikoCyan(); sw.on = on;
    sw.frame = CGRectMake(card.bounds.size.width - 20 - sw.bounds.size.width, y, sw.bounds.size.width, 31);
    [sw addTarget:self action:sel forControlEvents:UIControlEventValueChanged];
    [card addSubview:sw];
}

- (void)hdChanged:(UISwitch *)s     { TikoSetBool(@"upload_hd", s.on); TikoToast(s.on ? @"TikoHD · HD flag ON" : @"TikoHD · HD flag OFF"); }
- (void)presetChanged:(UISwitch *)s { TikoSetBool(@"tikohd_force_preset", s.on); TikoToast(s.on ? @"TikoHD · HD export ON" : @"TikoHD · HD export OFF"); }

- (void)bgTap:(UITapGestureRecognizer *)g {
    UIView *card = [self viewWithTag:0x71D1];
    if (CGRectContainsPoint(card.frame, [g locationInView:self])) return;
    [UIView animateWithDuration:0.18 animations:^{ self.alpha = 0; }
                     completion:^(BOOL _) { [self removeFromSuperview]; }];
}
@end

#pragma mark - Gesture → panel

@interface TikoHDGesture : NSObject
+ (instancetype)shared;
- (void)show:(UILongPressGestureRecognizer *)g;
@end
@implementation TikoHDGesture
+ (instancetype)shared {
    static TikoHDGesture *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [TikoHDGesture new]; });
    return s;
}
- (void)show:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    UIWindow *win = TikoKeyWindow();
    if (!win || [win viewWithTag:0x71D0]) return;     // avoid duplicates
    TikoHDPanel *p = [[TikoHDPanel alloc] initWithFrame:win.bounds];
    p.tag = 0x71D0;
    [win addSubview:p];
}
@end

#pragma mark - Layer 1: HD-eligibility flag (the proven BHTikTok mechanism)

%hook ACCCreationPublishAction
- (BOOL)is_open_hd { if (HD_ON) return YES; return %orig; }
- (void)setIs_open_hd:(BOOL)a { if (HD_ON) { %orig(YES); TikoToast(@"TikoHD · HD forced ✓"); } else %orig(a); }
- (BOOL)is_have_hd { if (HD_ON) return YES; return %orig; }
- (void)setIs_have_hd:(BOOL)a { if (HD_ON) %orig(YES); else %orig(a); }
%end

#pragma mark - Layer 2: export-preset rescue (our improvement, opt-in)

static NSString *TikoFixPreset(AVAsset *asset, NSString *preset) {
    if (!PRESET_ON || ![preset isKindOfClass:NSString.class] || !asset) return preset;
    static NSSet *degrade; static dispatch_once_t once;
    dispatch_once(&once, ^{
        degrade = [NSSet setWithArray:@[
            AVAssetExportPreset640x480, AVAssetExportPreset960x540,
            AVAssetExportPresetLowQuality, AVAssetExportPresetMediumQuality
        ]];
    });
    if (![degrade containsObject:preset]) return preset;

    // Only rescue genuine HD masters — never touch thumbnails/small clips/other flows.
    CGFloat maxDim = 0;
    @try {
        for (AVAssetTrack *t in [asset tracksWithMediaType:AVMediaTypeVideo]) {
            CGSize n = CGSizeApplyAffineTransform(t.naturalSize, t.preferredTransform);
            maxDim = MAX(maxDim, MAX(fabs(n.width), fabs(n.height)));
        }
    } @catch (__unused id e) { return preset; }
    if (maxDim < 1080) return preset;

    // Substitute only to a preset the asset actually supports; prefer HEVC, else universal H.264 1080p.
    NSArray *ok = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    if ([ok containsObject:AVAssetExportPresetHEVCHighestQuality]) return AVAssetExportPresetHEVCHighestQuality;
    if ([ok containsObject:AVAssetExportPreset1920x1080]) return AVAssetExportPreset1920x1080;
    return preset;
}

%hook AVAssetExportSession
+ (instancetype)exportSessionWithAsset:(AVAsset *)asset presetName:(NSString *)presetName {
    return %orig(asset, TikoFixPreset(asset, presetName));
}
- (instancetype)initWithAsset:(AVAsset *)asset presetName:(NSString *)presetName {
    return %orig(asset, TikoFixPreset(asset, presetName));
}
%end

#pragma mark - Attach the settings gesture once per window

%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    if (self.windowLevel != UIWindowLevelNormal) return;   // skip alert/keyboard/system windows
    static char kAttached;
    if (objc_getAssociatedObject(self, &kAttached)) return;
    objc_setAssociatedObject(self, &kAttached, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UILongPressGestureRecognizer *g =
        [[UILongPressGestureRecognizer alloc] initWithTarget:TikoHDGesture.shared action:@selector(show:)];
    g.numberOfTouchesRequired = 2;
    g.minimumPressDuration = 0.8;
    g.cancelsTouchesInView = NO;
    [self addGestureRecognizer:g];
}
%end

#pragma mark - Anti-detection (lets the modded app PASS TikTok's login integrity check)

// TikTok's AAAASingularity + AAWEBootChecker integrity SDKs fingerprint the injected dylib and
// drop the device to near-zero trust, so the login server answers "Maximum attempts reached".
// We replicate BHTikTok's exact bypass: force TikTok's OWN jailbreak/integrity self-checks to
// report CLEAN. Selectors + jailbreak-path blocklist lifted verbatim from the real BHTikTokPlus.dylib.

static BOOL TikoNO(id s, SEL c)  { return NO; }
static BOOL TikoYES(id s, SEL c) { return YES; }
static void TikoVoid(id s, SEL c) {}

static BOOL TikoIsJBPath(NSString *p) {
    static NSSet *set; static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[
            @"/Applications/Cydia.app", @"/Applications/blackra1n.app", @"/Applications/FakeCarrier.app",
            @"/Applications/Icy.app", @"/Applications/IntelliScreen.app", @"/Applications/MxTube.app",
            @"/Applications/RockApp.app", @"/Applications/SBSettings.app", @"/Applications/WinterBoard.app",
            @"/.cydia_no_stash", @"/.installed_unc0ver", @"/.bootstrapped_electra",
            @"/usr/libexec/cydia/firmware.sh", @"/usr/libexec/ssh-keysign", @"/usr/libexec/sftp-server",
            @"/usr/bin/ssh", @"/usr/bin/sshd", @"/usr/sbin/sshd", @"/var/lib/cydia",
            @"/var/lib/dpkg/info/mobilesubstrate.md5sums", @"/var/log/apt",
            @"/usr/share/jailbreak/injectme.plist", @"/usr/sbin/frida-server",
            @"/Library/MobileSubstrate/CydiaSubstrate.dylib", @"/Library/TweakInject",
            @"/Library/MobileSubstrate/MobileSubstrate.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/LiveClock.plist",
            @"/Library/MobileSubstrate/DynamicLibraries/Veency.plist",
            @"/System/Library/LaunchDaemons/com.ikey.bbot.plist",
            @"/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist",
            @"/private/var/lib/cydia", @"/private/var/tmp/cydia.log", @"/private/var/cache/apt/",
            @"/private/var/lib/apt", @"/private/var/stash", @"/usr/lib/libjailbreak.dylib",
            @"/jb/amfid_payload.dylib", @"/jb/libjailbreak.dylib", @"/jb/jailbreakd.plist",
            @"/jb/offsets.plist", @"/jb/lzma", @"/hmd_tmp_file",
            @"/etc/apt/undecimus/undecimus.list", @"/etc/apt/sources.list.d/sileo.sources",
            @"/etc/apt/sources.list.d/electra.list", @"/etc/apt"
        ]];
    });
    if (![p isKindOfClass:NSString.class] || p.length == 0) return NO;
    if ([set containsObject:p]) return YES;
    return ([p hasPrefix:@"/Library/MobileSubstrate"] || [p hasPrefix:@"/var/jb"] ||
            [p hasPrefix:@"/private/var/jb"] || [p hasPrefix:@"/Library/TweakInject"]);
}

// Force TikTok's jailbreak/integrity verdict methods to report CLEAN, on EVERY class that defines them.
static void TikoInstallAntiDetect(void) {
    struct { const char *sel; IMP imp; } T[] = {
        {"isJailBroken", (IMP)TikoNO},
        {"btd_isJailBroken", (IMP)TikoNO},
        {"isJailbrokenWithSkipAdvancedJailbreakValidation:", (IMP)TikoNO},
        {"_pipo_isJailBrokenDeviceWithProductID:orderID:", (IMP)TikoNO},
        {"isAppStoreReceiptSandbox", (IMP)TikoNO},
        {"isDebugBuild", (IMP)TikoNO},
        {"isFromAppStore", (IMP)TikoYES},
        {"isAppStoreChannel", (IMP)TikoYES},
    };
    const int NT = (int)(sizeof(T) / sizeof(T[0]));
    SEL sels[16];
    for (int t = 0; t < NT; t++) sels[t] = sel_registerName(T[t].sel);
    unsigned int n = 0;
    Class *all = objc_copyClassList(&n);
    for (unsigned i = 0; i < n; i++) {
        for (int pass = 0; pass < 2; pass++) {                 // pass 0 = instance, pass 1 = class methods
            Class cc = pass ? object_getClass(all[i]) : all[i];
            unsigned int mc = 0;
            Method *ms = class_copyMethodList(cc, &mc);
            for (unsigned j = 0; j < mc; j++) {
                SEL s = method_getName(ms[j]);
                for (int t = 0; t < NT; t++) if (s == sels[t]) { method_setImplementation(ms[j], T[t].imp); break; }
            }
            if (ms) free(ms);
        }
    }
    if (all) free(all);

    // Best-effort: no-op the two integrity SDKs' detectors/reporters (safe no-ops if absent).
    void (^stub)(const char *, const char *, IMP) = ^(const char *cls, const char *sel, IMP imp) {
        Class c = objc_getClass(cls); if (!c) return;
        SEL s = sel_registerName(sel);
        for (int pass = 0; pass < 2; pass++) {
            Method m = class_getInstanceMethod(pass ? object_getClass(c) : c, s);
            if (m) method_setImplementation(m, imp);
        }
    };
    stub("AAWEBootChecker", "shouldCheckTargetPath:", (IMP)TikoNO);
    stub("AAASingularityMKHelper", "recordAllLoadedImages", (IMP)TikoVoid);
    stub("AAASingularityMKHelper", "registerAddImageCallback", (IMP)TikoVoid);
}

%hook NSFileManager
- (BOOL)fileExistsAtPath:(NSString *)path {
    if (TikoIsJBPath(path)) return NO;
    return %orig;
}
- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    if (TikoIsJBPath(path)) { if (isDirectory) *isDirectory = NO; return NO; }
    return %orig;
}
%end

#pragma mark - Defaults + boot

%ctor {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        @"upload_hd": @YES,
        @"tikohd_force_preset": @NO,
    }];
    TikoInstallAntiDetect();   // must run before the login flow consults the integrity verdict
}
