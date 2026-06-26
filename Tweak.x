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

#pragma mark - Defaults (HD on out of the box; export beta off)

%ctor {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        @"upload_hd": @YES,
        @"tikohd_force_preset": @NO,
    }];
}
