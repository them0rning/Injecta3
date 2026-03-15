/*
 * MainViewController.m  —  CamInject companion app
 *
 * Lets the user:
 *   • Pick an image from Photos
 *   • Flip it horizontally or vertically
 *   • Rotate it 90° CW or CCW
 *   • Toggle injection on/off with a live switch
 *   • Apply — saves inject.png + config.plist and notifies the tweak
 *
 * All writes go to /var/jb/Library/CameraInject/ (rootless path).
 */

#import "MainViewController.h"
#import <CoreFoundation/CoreFoundation.h>

// ── Paths ──────────────────────────────────────────────────────────────────
static NSString *const kLibDir     = @"/var/jb/Library/CameraInject";
static NSString *const kImagePath  = @"/var/jb/Library/CameraInject/inject.png";
static NSString *const kConfigPath = @"/var/jb/Library/CameraInject/config.plist";
static NSString *const kNotifyKey  = @"com.yourname.camerainject.reload";

// ── Colours (dark dev-tool palette) ───────────────────────────────────────
#define RGB(r,g,b) [UIColor colorWithRed:(r)/255.0 green:(g)/255.0 blue:(b)/255.0 alpha:1]
#define RGBA(r,g,b,a) [UIColor colorWithRed:(r)/255.0 green:(g)/255.0 blue:(b)/255.0 alpha:(a)]

// ── Small helper: rounded pill button ─────────────────────────────────────
static UIButton *MakePillButton(NSString *title, UIColor *bg) {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.backgroundColor = bg;
    btn.layer.cornerRadius = 12;
    btn.layer.masksToBounds = YES;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    return btn;
}

// ── Small helper: section label ────────────────────────────────────────────
static UILabel *MakeSectionLabel(NSString *text) {
    UILabel *lbl = [[UILabel alloc] init];
    lbl.text = text.uppercaseString;
    lbl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    lbl.textColor = RGBA(160,160,180,1);
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc]
        initWithString:text.uppercaseString
            attributes:@{
                NSKernAttributeName: @(1.4),
                NSForegroundColorAttributeName: RGBA(160,160,180,1),
                NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightBold]
            }];
    lbl.attributedText = as;
    return lbl;
}

// ============================================================================
@interface MainViewController () <UIImagePickerControllerDelegate,
                                   UINavigationControllerDelegate>

// State
@property (nonatomic, strong) UIImage *baseImage;   // original picked image
@property (nonatomic, assign) CGFloat  rotateDeg;   // accumulated rotation
@property (nonatomic, assign) BOOL     flipH;
@property (nonatomic, assign) BOOL     flipV;
@property (nonatomic, assign) BOOL     injectionEnabled;

// UI
@property (nonatomic, strong) UIScrollView    *scrollView;
@property (nonatomic, strong) UIView          *contentView;

@property (nonatomic, strong) UILabel         *titleLabel;
@property (nonatomic, strong) UISwitch        *enableSwitch;
@property (nonatomic, strong) UILabel         *switchLabel;

@property (nonatomic, strong) UIImageView     *previewImageView;
@property (nonatomic, strong) UILabel         *previewPlaceholderLabel;

@property (nonatomic, strong) UIButton        *choosePhotoBtn;

@property (nonatomic, strong) UIButton        *rotLeftBtn;
@property (nonatomic, strong) UIButton        *rotRightBtn;
@property (nonatomic, strong) UIButton        *flipHBtn;
@property (nonatomic, strong) UIButton        *flipVBtn;

@property (nonatomic, strong) UIButton        *applyBtn;
@property (nonatomic, strong) UILabel         *statusLabel;

@end

@implementation MainViewController

// ============================================================================
#pragma mark - Lifecycle
// ============================================================================

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadConfig];
    [self buildUI];
    [self loadSavedImage];
    [self refreshPreview];
}

// ============================================================================
#pragma mark - Config I/O
// ============================================================================

- (void)loadConfig {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:kLibDir]) {
        [fm createDirectoryAtPath:kLibDir
      withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSDictionary *cfg = [NSDictionary dictionaryWithContentsOfFile:kConfigPath];
    self.injectionEnabled = cfg[@"enabled"] ? [cfg[@"enabled"] boolValue] : YES;
}

- (void)saveConfig {
    NSMutableDictionary *cfg = [NSMutableDictionary dictionary];
    cfg[@"enabled"]   = @(self.injectionEnabled);
    cfg[@"imagePath"] = kImagePath;
    [cfg writeToFile:kConfigPath atomically:YES];
}

- (void)loadSavedImage {
    UIImage *img = [UIImage imageWithContentsOfFile:kImagePath];
    if (img) {
        self.baseImage  = img;
        self.rotateDeg  = 0;
        self.flipH      = NO;
        self.flipV      = NO;
    }
}

// ============================================================================
#pragma mark - Build UI
// ============================================================================

- (void)buildUI {
    self.view.backgroundColor = RGB(12, 12, 20);

    // ── Scroll container ──────────────────────────────────────────────────
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    NSLayoutConstraint *contentWidth = [self.contentView.widthAnchor
        constraintEqualToAnchor:self.scrollView.widthAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        contentWidth
    ]];

    UIView *cv = self.contentView;
    CGFloat pad = 20;

    // ── Header row ────────────────────────────────────────────────────────
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.text = @"CamInject";
    self.titleLabel.font = [UIFont systemFontOfSize:30 weight:UIFontWeightHeavy];
    self.titleLabel.textColor = UIColor.whiteColor;
    [cv addSubview:self.titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = @"Camera Feed Injection";
    subtitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    subtitleLabel.textColor = RGBA(120,120,150,1);
    [cv addSubview:subtitleLabel];

    // ── Enable toggle card ─────────────────────────────────────────────────
    UIView *toggleCard = [self makeCard];
    [cv addSubview:toggleCard];

    UILabel *toggleTitle = [[UILabel alloc] init];
    toggleTitle.translatesAutoresizingMaskIntoConstraints = NO;
    toggleTitle.text = @"Injection Active";
    toggleTitle.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    toggleTitle.textColor = UIColor.whiteColor;
    [toggleCard addSubview:toggleTitle];

    self.switchLabel = [[UILabel alloc] init];
    self.switchLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.switchLabel.font = [UIFont systemFontOfSize:13];
    self.switchLabel.textColor = RGBA(160,160,180,1);
    [toggleCard addSubview:self.switchLabel];

    self.enableSwitch = [[UISwitch alloc] init];
    self.enableSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    self.enableSwitch.onTintColor = RGB(50, 200, 120);
    self.enableSwitch.on = self.injectionEnabled;
    [self.enableSwitch addTarget:self action:@selector(toggleChanged:)
                forControlEvents:UIControlEventValueChanged];
    [toggleCard addSubview:self.enableSwitch];

    // ── Preview card ───────────────────────────────────────────────────────
    UIView *previewCard = [self makeCard];
    [cv addSubview:previewCard];

    UILabel *previewSection = MakeSectionLabel(@"Preview");
    [previewCard addSubview:previewSection];

    self.previewImageView = [[UIImageView alloc] init];
    self.previewImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.previewImageView.backgroundColor = RGB(22, 22, 35);
    self.previewImageView.layer.cornerRadius = 10;
    self.previewImageView.layer.masksToBounds = YES;
    [previewCard addSubview:self.previewImageView];

    self.previewPlaceholderLabel = [[UILabel alloc] init];
    self.previewPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewPlaceholderLabel.text = @"No image selected\nTap 'Choose Photo' below";
    self.previewPlaceholderLabel.numberOfLines = 2;
    self.previewPlaceholderLabel.textAlignment = NSTextAlignmentCenter;
    self.previewPlaceholderLabel.font = [UIFont systemFontOfSize:15];
    self.previewPlaceholderLabel.textColor = RGBA(100,100,130,1);
    [self.previewImageView addSubview:self.previewPlaceholderLabel];

    // ── Choose photo button ────────────────────────────────────────────────
    self.choosePhotoBtn = MakePillButton(@"  Choose Photo", RGB(40, 110, 255));
    [self.choosePhotoBtn addTarget:self action:@selector(choosePotoTapped)
                  forControlEvents:UIControlEventTouchUpInside];
    [cv addSubview:self.choosePhotoBtn];

    // ── Transform card ─────────────────────────────────────────────────────
    UIView *transformCard = [self makeCard];
    [cv addSubview:transformCard];

    UILabel *transformSection = MakeSectionLabel(@"Transform");
    [transformCard addSubview:transformSection];

    // Row 1: Rotate
    UILabel *rotLabel = [[UILabel alloc] init];
    rotLabel.translatesAutoresizingMaskIntoConstraints = NO;
    rotLabel.text = @"Rotate";
    rotLabel.font = [UIFont systemFontOfSize:14];
    rotLabel.textColor = RGBA(180,180,200,1);
    [transformCard addSubview:rotLabel];

    self.rotLeftBtn  = MakePillButton(@"↺  90° Left",  RGB(55, 55, 80));
    self.rotRightBtn = MakePillButton(@"↻  90° Right", RGB(55, 55, 80));
    [self.rotLeftBtn  addTarget:self action:@selector(rotateCCW)
               forControlEvents:UIControlEventTouchUpInside];
    [self.rotRightBtn addTarget:self action:@selector(rotateCW)
               forControlEvents:UIControlEventTouchUpInside];
    [transformCard addSubview:self.rotLeftBtn];
    [transformCard addSubview:self.rotRightBtn];

    // Row 2: Flip
    UILabel *flipLabel = [[UILabel alloc] init];
    flipLabel.translatesAutoresizingMaskIntoConstraints = NO;
    flipLabel.text = @"Flip";
    flipLabel.font = [UIFont systemFontOfSize:14];
    flipLabel.textColor = RGBA(180,180,200,1);
    [transformCard addSubview:flipLabel];

    self.flipHBtn = MakePillButton(@"⇔  Horizontal", RGB(55, 55, 80));
    self.flipVBtn = MakePillButton(@"⇕  Vertical",   RGB(55, 55, 80));
    [self.flipHBtn addTarget:self action:@selector(flipHorizontal)
           forControlEvents:UIControlEventTouchUpInside];
    [self.flipVBtn addTarget:self action:@selector(flipVertical)
           forControlEvents:UIControlEventTouchUpInside];
    [transformCard addSubview:self.flipHBtn];
    [transformCard addSubview:self.flipVBtn];

    // ── Apply button ───────────────────────────────────────────────────────
    self.applyBtn = MakePillButton(@"Apply & Activate", RGB(50, 200, 120));
    self.applyBtn.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    [self.applyBtn addTarget:self action:@selector(applyTapped)
            forControlEvents:UIControlEventTouchUpInside];
    [cv addSubview:self.applyBtn];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.text = @"";
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.textColor = RGB(50, 200, 120);
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [cv addSubview:self.statusLabel];

    // ── Layout ─────────────────────────────────────────────────────────────
    [NSLayoutConstraint activateConstraints:@[

        // Title
        [self.titleLabel.topAnchor constraintEqualToAnchor:cv.topAnchor constant:28],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:pad],

        [subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:pad],

        // Toggle card
        [toggleCard.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:24],
        [toggleCard.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:pad],
        [toggleCard.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-pad],

        [toggleTitle.topAnchor constraintEqualToAnchor:toggleCard.topAnchor constant:16],
        [toggleTitle.leadingAnchor constraintEqualToAnchor:toggleCard.leadingAnchor constant:16],

        [self.switchLabel.topAnchor constraintEqualToAnchor:toggleTitle.bottomAnchor constant:4],
        [self.switchLabel.leadingAnchor constraintEqualToAnchor:toggleCard.leadingAnchor constant:16],
        [self.switchLabel.bottomAnchor constraintEqualToAnchor:toggleCard.bottomAnchor constant:-16],

        [self.enableSwitch.centerYAnchor constraintEqualToAnchor:toggleCard.centerYAnchor],
        [self.enableSwitch.trailingAnchor constraintEqualToAnchor:toggleCard.trailingAnchor constant:-16],

        // Preview card
        [previewCard.topAnchor constraintEqualToAnchor:toggleCard.bottomAnchor constant:16],
        [previewCard.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:pad],
        [previewCard.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-pad],

        [previewSection.topAnchor constraintEqualToAnchor:previewCard.topAnchor constant:16],
        [previewSection.leadingAnchor constraintEqualToAnchor:previewCard.leadingAnchor constant:16],

        [self.previewImageView.topAnchor constraintEqualToAnchor:previewSection.bottomAnchor constant:12],
        [self.previewImageView.leadingAnchor constraintEqualToAnchor:previewCard.leadingAnchor constant:16],
        [self.previewImageView.trailingAnchor constraintEqualToAnchor:previewCard.trailingAnchor constant:-16],
        [self.previewImageView.heightAnchor constraintEqualToConstant:220],
        [self.previewImageView.bottomAnchor constraintEqualToAnchor:previewCard.bottomAnchor constant:-16],

        [self.previewPlaceholderLabel.centerXAnchor constraintEqualToAnchor:self.previewImageView.centerXAnchor],
        [self.previewPlaceholderLabel.centerYAnchor constraintEqualToAnchor:self.previewImageView.centerYAnchor],

        // Choose photo
        [self.choosePhotoBtn.topAnchor constraintEqualToAnchor:previewCard.bottomAnchor constant:16],
        [self.choosePhotoBtn.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:pad],
        [self.choosePhotoBtn.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-pad],
        [self.choosePhotoBtn.heightAnchor constraintEqualToConstant:52],

        // Transform card
        [transformCard.topAnchor constraintEqualToAnchor:self.choosePhotoBtn.bottomAnchor constant:16],
        [transformCard.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:pad],
        [transformCard.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-pad],

        [transformSection.topAnchor constraintEqualToAnchor:transformCard.topAnchor constant:16],
        [transformSection.leadingAnchor constraintEqualToAnchor:transformCard.leadingAnchor constant:16],

        // Rotate row
        [rotLabel.topAnchor constraintEqualToAnchor:transformSection.bottomAnchor constant:14],
        [rotLabel.leadingAnchor constraintEqualToAnchor:transformCard.leadingAnchor constant:16],

        [self.rotLeftBtn.topAnchor constraintEqualToAnchor:rotLabel.bottomAnchor constant:8],
        [self.rotLeftBtn.leadingAnchor constraintEqualToAnchor:transformCard.leadingAnchor constant:16],
        [self.rotLeftBtn.trailingAnchor constraintEqualToAnchor:transformCard.centerXAnchor constant:-6],
        [self.rotLeftBtn.heightAnchor constraintEqualToConstant:44],

        [self.rotRightBtn.topAnchor constraintEqualToAnchor:rotLabel.bottomAnchor constant:8],
        [self.rotRightBtn.leadingAnchor constraintEqualToAnchor:transformCard.centerXAnchor constant:6],
        [self.rotRightBtn.trailingAnchor constraintEqualToAnchor:transformCard.trailingAnchor constant:-16],
        [self.rotRightBtn.heightAnchor constraintEqualToConstant:44],

        // Flip row
        [flipLabel.topAnchor constraintEqualToAnchor:self.rotLeftBtn.bottomAnchor constant:14],
        [flipLabel.leadingAnchor constraintEqualToAnchor:transformCard.leadingAnchor constant:16],

        [self.flipHBtn.topAnchor constraintEqualToAnchor:flipLabel.bottomAnchor constant:8],
        [self.flipHBtn.leadingAnchor constraintEqualToAnchor:transformCard.leadingAnchor constant:16],
        [self.flipHBtn.trailingAnchor constraintEqualToAnchor:transformCard.centerXAnchor constant:-6],
        [self.flipHBtn.heightAnchor constraintEqualToConstant:44],

        [self.flipVBtn.topAnchor constraintEqualToAnchor:flipLabel.bottomAnchor constant:8],
        [self.flipVBtn.leadingAnchor constraintEqualToAnchor:transformCard.centerXAnchor constant:6],
        [self.flipVBtn.trailingAnchor constraintEqualToAnchor:transformCard.trailingAnchor constant:-16],
        [self.flipVBtn.heightAnchor constraintEqualToConstant:44],
        [self.flipVBtn.bottomAnchor constraintEqualToAnchor:transformCard.bottomAnchor constant:-16],

        // Apply
        [self.applyBtn.topAnchor constraintEqualToAnchor:transformCard.bottomAnchor constant:24],
        [self.applyBtn.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:pad],
        [self.applyBtn.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-pad],
        [self.applyBtn.heightAnchor constraintEqualToConstant:56],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.applyBtn.bottomAnchor constant:12],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:pad],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-pad],
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-40],
    ]];

    [self updateSwitchLabel];
}

// ============================================================================
#pragma mark - Card factory
// ============================================================================

- (UIView *)makeCard {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = RGB(22, 22, 38);
    card.layer.cornerRadius = 16;
    card.layer.masksToBounds = YES;
    // Subtle border
    card.layer.borderWidth = 1;
    card.layer.borderColor = RGBA(255,255,255,0.06).CGColor;
    return card;
}

// ============================================================================
#pragma mark - Actions
// ============================================================================

- (void)toggleChanged:(UISwitch *)sw {
    self.injectionEnabled = sw.on;
    [self updateSwitchLabel];
}

- (void)updateSwitchLabel {
    self.switchLabel.text = self.injectionEnabled
        ? @"Fake image will be shown to all camera apps"
        : @"Real camera feed will pass through";
    self.switchLabel.textColor = self.injectionEnabled
        ? RGB(50, 200, 120) : RGBA(160,100,100,1);
}

- (void)choosePotoTapped {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        [self showAlert:@"Photos not available" message:@"Cannot access photo library on this device."];
        return;
    }
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate   = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)rotateCCW {
    if (!self.baseImage) return;
    self.rotateDeg = fmod(self.rotateDeg - 90 + 360, 360);
    [self refreshPreview];
}

- (void)rotateCW {
    if (!self.baseImage) return;
    self.rotateDeg = fmod(self.rotateDeg + 90, 360);
    [self refreshPreview];
}

- (void)flipHorizontal {
    if (!self.baseImage) return;
    self.flipH = !self.flipH;
    [self highlightButton:self.flipHBtn active:self.flipH];
    [self refreshPreview];
}

- (void)flipVertical {
    if (!self.baseImage) return;
    self.flipV = !self.flipV;
    [self highlightButton:self.flipVBtn active:self.flipV];
    [self refreshPreview];
}

- (void)highlightButton:(UIButton *)btn active:(BOOL)active {
    btn.backgroundColor = active ? RGB(40, 110, 255) : RGB(55, 55, 80);
}

- (void)applyTapped {
    if (!self.baseImage) {
        [self showAlert:@"No Image" message:@"Please choose a photo first."];
        return;
    }

    // Build final transformed image
    UIImage *final = [self buildTransformedImage];

    // Save as PNG
    NSData *png = UIImagePNGRepresentation(final);
    NSError *err = nil;
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:kLibDir]) {
        [fm createDirectoryAtPath:kLibDir withIntermediateDirectories:YES
                       attributes:nil error:&err];
    }
    BOOL ok = [png writeToFile:kImagePath options:NSDataWritingAtomic error:&err];
    if (!ok) {
        [self showAlert:@"Save Failed" message:err.localizedDescription ?: @"Unknown error"];
        return;
    }

    // Write config
    self.injectionEnabled = self.enableSwitch.on;
    [self saveConfig];

    // Notify tweak to reload
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.yourname.camerainject.reload"),
        NULL, NULL, YES
    );

    // Feedback
    [self showStatus:@"✓ Applied — camera injection updated"];
    UINotificationFeedbackGenerator *gen = [[UINotificationFeedbackGenerator alloc] init];
    [gen notificationOccurred:UINotificationFeedbackTypeSuccess];
}

// ============================================================================
#pragma mark - Image transform
// ============================================================================

- (UIImage *)buildTransformedImage {
    UIImage *img = self.baseImage;
    CGSize  size = img.size;

    // Determine final size after rotation
    BOOL swap = (fmod(self.rotateDeg, 180) != 0); // 90 or 270 → swap W/H
    CGSize outSize = swap
        ? CGSizeMake(size.height, size.width)
        : CGSizeMake(size.width,  size.height);

    UIGraphicsBeginImageContextWithOptions(outSize, NO, img.scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    // Move origin to centre
    CGContextTranslateCTM(ctx, outSize.width / 2, outSize.height / 2);

    // Apply flips
    CGContextScaleCTM(ctx,
        self.flipH ? -1 : 1,
        self.flipV ? -1 : 1);

    // Apply rotation
    CGContextRotateCTM(ctx, self.rotateDeg * M_PI / 180.0);

    // Draw (origin at centre)
    [img drawInRect:CGRectMake(-size.width / 2, -size.height / 2, size.width, size.height)];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result ?: img;
}

- (void)refreshPreview {
    if (!self.baseImage) {
        self.previewImageView.image = nil;
        self.previewPlaceholderLabel.hidden = NO;
        return;
    }
    self.previewPlaceholderLabel.hidden = YES;
    self.previewImageView.image = [self buildTransformedImage];
}

// ============================================================================
#pragma mark - UIImagePickerControllerDelegate
// ============================================================================

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info
{
    UIImage *img = info[UIImagePickerControllerEditedImage]
                ?: info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:nil];

    if (!img) return;
    self.baseImage = img;
    self.rotateDeg = 0;
    self.flipH     = NO;
    self.flipV     = NO;
    [self highlightButton:self.flipHBtn active:NO];
    [self highlightButton:self.flipVBtn active:NO];
    [self refreshPreview];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

// ============================================================================
#pragma mark - Helpers
// ============================================================================

- (void)showStatus:(NSString *)msg {
    self.statusLabel.alpha = 1;
    self.statusLabel.text  = msg;
    [UIView animateWithDuration:0.4 delay:3.0 options:0 animations:^{
        self.statusLabel.alpha = 0;
    } completion:nil];
}

- (void)showAlert:(NSString *)title message:(NSString *)msg {
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:title message:msg
        preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
