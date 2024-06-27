//
//  HudViewController.m
//  FlyingSwallow
//
//  Created by koupoo on 12-12-21. Email: koupoo@126.com
//  Copyright (c) 2012年 www.hexairbot.com. All rights reserved.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License V2
//  as published by the Free Software Foundation.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "HudViewController.h"
#import <mach/mach_time.h>
#import "Macros.h"
#import "util.h"
#import "BlockViewStyle1.h"
#import "Transmitter.h"
#import "BasicInfoManager.h"
#import "OSDCommon.h"
#import "HelpViewController.h"
#import <MediaPlayer/MediaPlayer.h>
#import <CoreMotion/CoreMotion.h>


#define UDP_SERVER_HOST @"192.168.0.1"
#define UDP_SERVER_PORT 6000

#define kThrottleFineTuningStep 0.03
#define kBeginnerElevatorChannelRatio  0.5
#define kBeginnerAileronChannelRatio   0.5
#define kBeginnerRudderChannelRatio    0.0
#define kBeginnerThrottleChannelRatio  0.8

#define kCheckDuration 0.1 //s

static uint64_t take_off_start_time = 0;

static inline float sign(float value)
{
	float result = 1.0;
	if(value < 0)
		result = -1.0;
	
	return result;
}

typedef enum flight_state{
    flight_state_taking_off,
    flight_state_angle,
    flight_state_horizon,
    flight_state_baro,
    flight_state_sonar,
    flight_state_headfree
}flight_state_t;


@interface HudViewController (){
    CGPoint joystickRightCurrentPosition, joystickLeftCurrentPosition;
    CGPoint joystickRightInitialPosition, joystickLeftInitialPosition;
    BOOL buttonRightPressed, buttonLeftPressed;
    CGPoint rightCenter, leftCenter;
    
    float joystickAlpha;
    
    BOOL isLeftHanded;
    BOOL accModeEnabled;
    BOOL accModeReady;
    
    float rightJoyStickOperableRadius;
    float leftJoyStickOperableRadius;
    
    BOOL isTransmitting;
    
    BOOL rudderIsLocked;
    BOOL throttleIsLocked;
    
    CGPoint rudderLockButtonCenter;
    CGPoint throttleUpButtonCenter;
    CGPoint throttleDownButtonCenter;
    CGPoint upIndicatorImageViewCenter;
    CGPoint downIndicatorImageViewCenter;
    
    CGPoint leftHandedRudderLockButtonCenter;
    CGPoint leftHandedThrottleUpButtonCenter;
    CGPoint leftHandedThrottleDownButtonCenter;
    CGPoint leftHandedUpIndicatorImageViewCenter;
    CGPoint leftHandedDownIndicatorImageViewCenter;
    
    NSMutableDictionary *blockViewDict;
    
    BOOL isAutoTakingOff;
    NSTimer *throttleTimer;
    

    int checkCnt;
    int accTimeCnt;
    
    
#define kAltArrayMaxLen 6
    float altArray[kAltArrayMaxLen];
    
    
    int altArrayVaildLen;
    
    
    flight_state_t flightState;
    OSDViewController *osdVC;
}

@property(nonatomic, strong) Channel *aileronChannel;
@property(nonatomic, strong) Channel *elevatorChannel;
@property(nonatomic, strong) Channel *rudderChannel;
@property(nonatomic, strong) Channel *throttleChannel;
@property(nonatomic, strong) Channel *aux1Channel;
@property(nonatomic, strong) Channel *aux2Channel;
@property(nonatomic, strong) Channel *aux3Channel;
@property(nonatomic, strong) Channel *aux4Channel;


@property(nonatomic, strong) Settings *settings;

@property(nonatomic, strong) SettingsMenuViewController *settingMenuVC;
@property(nonatomic, strong) HelpViewController *helpVC;

@end


@implementation HudViewController
@synthesize debugTextView;
@synthesize aileronChannel = _aileronChannel;
@synthesize elevatorChannel = _elevatorChannel;
@synthesize rudderChannel = _rudderChannel;
@synthesize throttleChannel = _throttleChannel;
@synthesize aux1Channel = _aux1Channel;
@synthesize aux2Channel = _aux2Channel;
@synthesize aux3Channel = _aux3Channel;
@synthesize aux4Channel = _aux4Channel;



@synthesize settings = _settings;

@synthesize settingMenuVC = _settingMenuVC;
@synthesize helpVC = _helpVC;

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationLandscapeLeft);
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations{
    return UIInterfaceOrientationMaskLandscapeLeft;
}

- (BOOL)shouldAutorotate{
    return YES;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dismissSettingsMenuView) name:kNotificationDismissSettingsMenuView object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dismissHelpView) name:kNotificationDismissHelpView object:nil];
        
        NSString *documentsDir= [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        NSString *userSettingsFilePath = [documentsDir stringByAppendingPathComponent:@"Settings.plist"];
        
        _settings = [[Settings alloc] initWithSettingsFile:userSettingsFilePath];
        
        if ([_settings.flexbotVersion isEqualToString:@"1.5.0"]) {
            [[BasicInfoManager sharedManager] setIsFullDuplex:YES];
        }
        else{
            [[BasicInfoManager sharedManager] setIsFullDuplex:NO];
        }
        
        UIDevice *device = [UIDevice currentDevice];
        device.batteryMonitoringEnabled = YES;
        [device addObserver:self forKeyPath:@"batteryLevel" options:NSKeyValueObservingOptionNew context:nil];
        
        CMMotionManager *motionManager = [[BasicInfoManager sharedManager] motionManager];
        
        if(motionManager.gyroAvailable == 0 && motionManager.accelerometerAvailable == 1)
        {
            //Only accelerometer
            motionManager.accelerometerUpdateInterval = 1.0 / 40;
            [motionManager startAccelerometerUpdates];
            NSLog(@"ACCELERO     [OK]");
        } else if (motionManager.deviceMotionAvailable == 1){
            //Accelerometer + gyro
            motionManager.deviceMotionUpdateInterval = 1.0 / 40;
            [motionManager startDeviceMotionUpdates];
            NSLog(@"ACCELERO     [OK]");
            NSLog(@"GYRO         [OK]");
        } else {
            NSLog(@"DEVICE MOTION ERROR - DISABLE");
            accModeEnabled = FALSE;
        }
        
        [self setAcceleroRotationWithPhi:0.0 withTheta:0.0 withPsi:0.0];
        
        
        [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)(1.0 / 40) target:self selector:@selector(motionDataHandler) userInfo:nil repeats:YES];
    }
    return self;
}

- (void)viewDidLoad{
    [super viewDidLoad];
    
    rudderLockButtonCenter = rudderLockButton.center;
    throttleUpButtonCenter = throttleUpButton.center;
    throttleDownButtonCenter = throttleDownButton.center;
    upIndicatorImageViewCenter = upIndicatorImageView.center;
    downIndicatorImageViewCenter = downIndicatorImageView.center;
    
    float hudFrameWidth = [[UIScreen mainScreen] bounds].size.height;
    
    leftHandedRudderLockButtonCenter = CGPointMake(hudFrameWidth - rudderLockButtonCenter.x, rudderLockButtonCenter.y);
    leftHandedThrottleUpButtonCenter = CGPointMake(hudFrameWidth - throttleUpButtonCenter.x, throttleUpButtonCenter.y);
    leftHandedThrottleDownButtonCenter = CGPointMake(hudFrameWidth - throttleDownButtonCenter.x, throttleDownButtonCenter.y);
    leftHandedUpIndicatorImageViewCenter = CGPointMake(hudFrameWidth - upIndicatorImageViewCenter.x, upIndicatorImageViewCenter.y);
    leftHandedDownIndicatorImageViewCenter = CGPointMake(hudFrameWidth - downIndicatorImageViewCenter.x, downIndicatorImageViewCenter.y);
        
    if (UIUserInterfaceIdiomPad == UI_USER_INTERFACE_IDIOM()) {
        rightJoyStickOperableRadius =  115;
        leftJoyStickOperableRadius  =  115;
    }
    else{
        rightJoyStickOperableRadius =  70;
        leftJoyStickOperableRadius  =  70;
    }

    _aileronChannel = [_settings channelByName:kChannelNameAileron];
    _elevatorChannel = [_settings channelByName:kChannelNameElevator];
    _rudderChannel = [_settings channelByName:kChannelNameRudder];
    _throttleChannel = [_settings channelByName:kChannelNameThrottle];
    _aux1Channel = [_settings channelByName:kChannelNameAUX1];
    _aux2Channel = [_settings channelByName:kChannelNameAUX2];
    _aux3Channel = [_settings channelByName:kChannelNameAUX3];
    _aux4Channel = [_settings channelByName:kChannelNameAUX4];

	rightCenter = CGPointMake(joystickRightThumbImageView.frame.origin.x + (joystickRightThumbImageView.frame.size.width / 2), joystickRightThumbImageView.frame.origin.y + (joystickRightThumbImageView.frame.size.height / 2));
	joystickRightInitialPosition = CGPointMake(rightCenter.x - (joystickRightBackgroundImageView.frame.size.width / 2), rightCenter.y - (joystickRightBackgroundImageView.frame.size.height / 2));
	leftCenter = CGPointMake(joystickLeftThumbImageView.frame.origin.x + (joystickLeftThumbImageView.frame.size.width / 2), joystickLeftThumbImageView.frame.origin.y + (joystickLeftThumbImageView.frame.size.height / 2));
	joystickLeftInitialPosition = CGPointMake(leftCenter.x - (joystickLeftBackgroundImageView.frame.size.width / 2), leftCenter.y - (joystickLeftBackgroundImageView.frame.size.height / 2));
    
	joystickLeftCurrentPosition = joystickLeftInitialPosition;
	joystickRightCurrentPosition = joystickRightInitialPosition;
	
    
    joystickAlpha = _settings.interfaceOpacity;
    
	//joystickAlpha = MIN(joystickRightBackgroundImageView.alpha, joystickRightThumbImageView.alpha);
	joystickRightBackgroundImageView.alpha = joystickRightThumbImageView.alpha = joystickAlpha;
	joystickLeftBackgroundImageView.alpha = joystickLeftThumbImageView.alpha = joystickAlpha;
	
	[self setBattery:(int)([UIDevice currentDevice].batteryLevel * 100)];
    
    [self updateJoystickCenter];
    
    [self updateStatusInfoLabel];
    [self updateThrottleValueLabel];
    
    [self settingsMenuViewController:nil leftHandedValueDidChange:_settings.isLeftHanded];
    [self settingsMenuViewController:nil accModeValueDidChange:_settings.isAccMode];
    
    [self updateJoysticksForAccModeChanged];
    
    if(isTransmitting == NO){
        [self startTransmission];
    }
    
    if(blockViewDict == nil){
        blockViewDict = [[NSMutableDictionary alloc] init];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkTransmitterState) name:kNotificationTransmitterStateDidChange object:nil];
    
    [[BasicInfoManager sharedManager] setDebugTextView:debugTextView];

    warningLabel.text = getLocalizeString(@"not connected");
    
    [self setSwitchButton:altHoldSwitchButton withValue:_settings.isAltHoldMode];
    
    if (_settings.isHeadFreeMode) {
        [_aux1Channel setValue:1];
    }
    else{
        [_aux1Channel setValue:-1];
    }

    if(_settings.isAltHoldMode){
        [_aux2Channel setValue:1];
    }
    else{
        [_aux2Channel setValue:-1];
    }
    
    [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(updateUI) userInfo:nil repeats:YES];
    
    //[NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(updateRSSI) userInfo:nil repeats:YES];
    
    if (_settings.isBeginnerMode) {
        UIAlertView *alertView = [[UIAlertView alloc]       initWithTitle:getLocalizeString(@"Beginner Mode")
                message:getLocalizeString(@"Beginner Mode Info")
                                                           delegate:self
                                                  cancelButtonTitle:getLocalizeString(@"OK")
                                                  otherButtonTitles:nil];
        [alertView show];
    }
    
    if (osdVC == nil) {
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
            osdVC = [[OSDViewController alloc] initWithNibName:@"OSDViewController" bundle:nil
                                                          data:[Transmitter sharedTransmitter].osdData];
            osdVC.view.center = CGPointMake(self.view.frame.size.width / 2.0, 300);
            /*
            osdVC.view.center = CGPointMake(self.view.frame.size.width - osdVC.view.frame.size.width / 2.0 - 10, 200);
            */
        }
        else{
            osdVC = [[OSDViewController alloc] initWithNibName:@"OSDViewController_iphone" bundle:nil
                                                          data:[Transmitter sharedTransmitter].osdData];
            osdVC.view.center = CGPointMake(self.view.frame.size.width / 2.0, 150);
            // osdVC = [[OSDViewController alloc] initWithNibName:@"OSDViewController_iPhone" bundle:nil
            //                                              data:[Transmitter sharedTransmitter].osdData];
            // osdVC.view.center = CGPointMake(self.view.frame.size.width / 2.0 - 10, 100);
        }
        
        [self.view insertSubview:osdVC.view belowSubview:joystickRightButton];
        
       // [[BasicInfoManager sharedManager] setOsdVC:osdVC];
    }
    
    if ([[BasicInfoManager sharedManager] isFullDuplex]) {
        osdVC.view.hidden = NO;
        infoView.hidden = NO;
    }
    else{
        osdVC.view.hidden = YES;
        infoView.hidden = YES;
    }
    
    flightState = flight_state_horizon;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleTryingToConnect:) name:kNotificationTryiingToConnect object:nil];
}

- (void)handleTryingToConnect:(NSNotification *)notification{
    NSString *target = [[notification userInfo] objectForKey:@"Target"];
    
    if ([target isEqualToString:@"FlexBLE"]) {
        if ( [_settings.flexbotVersion isEqualToString:@"1.5.0"] == NO) {
            _settings.flexbotVersion = @"1.5.0";
            [_settings save];
        }

        [[BasicInfoManager sharedManager] setIsFullDuplex:YES];
        
        osdVC.view.hidden = NO;
        infoView.hidden = NO;
    }
    else{
        _settings.flexbotVersion = @"1.0.0";
        [_settings save];
        [[BasicInfoManager sharedManager] setIsFullDuplex:NO];
        
        osdVC.view.hidden = YES;
        infoView.hidden = YES;
    }
}


- (void)viewDidUnload
{
    setttingButton = nil;
    joystickLeftButton = nil;
    joystickRightButton = nil;
    joystickLeftThumbImageView = nil;
    joystickLeftBackgroundImageView = nil;
    joystickRightThumbImageView = nil;
    joystickRightBackgroundImageView = nil;
    batteryLevelLabel = nil;
    batteryImageView = nil;
    _settingMenuVC = nil;
    _helpVC = nil;
    warningView = nil;
    warningLabel = nil;
    rudderLockButton = nil;
    statusInfoLabel = nil;
    throttleUpButton = nil;
    throttleDownButton = nil;
    downIndicatorImageView = nil;
    upIndicatorImageView = nil;
    throttleValueLabel = nil;
    [self setDebugTextView:nil];
    rollValueTextLabel = nil;
    pitchValueTextLabel = nil;
    altValueTextLabel = nil;
    headAngleValueTextLabel = nil;
    altHoldSwitchButton = nil;
    [super viewDidUnload];
    // Release any retained subviews of the main view.
}

- (void)didReceiveMemoryWarning{
    [super didReceiveMemoryWarning];
    _settingMenuVC = nil;
    _helpVC = nil;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kNotificationDismissSettingsMenuView object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kNotificationDismissHelpView object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kNotificationTransmitterStateDidChange object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kNotificationTryiingToConnect object:nil];
    
    [self stopTransmission];
    
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {  
    if ([keyPath isEqual:@"batteryLevel"] || [object isEqual:[UIDevice currentDevice]]) {  
        [self setBattery:(int)([UIDevice currentDevice].batteryLevel * 100)]; 
    }  
}  



#pragma mark SettingsMenuViewControllerDelegate Methods

- (void)settingsMenuViewController:(SettingsMenuViewController *)ctrl interfaceOpacityValueDidChange:(float)newValue{
    joystickAlpha = newValue;
    joystickLeftBackgroundImageView.alpha = joystickAlpha;
    joystickLeftThumbImageView.alpha = joystickAlpha;
    joystickRightBackgroundImageView.alpha = joystickAlpha;
    joystickRightThumbImageView.alpha = joystickAlpha;

}

- (void)settingsMenuViewController:(SettingsMenuViewController *)ctrl leftHandedValueDidChange:(BOOL)enabled{
    isLeftHanded = enabled;
    
    [self josystickButtonDidTouchUp:joystickLeftButton forEvent:nil];
    [self josystickButtonDidTouchUp:joystickRightButton forEvent:nil];

    if(isLeftHanded){
        joystickLeftThumbImageView.image = [UIImage imageNamed:@"Joystick_Manuel_RETINA.png"];
        joystickRightThumbImageView.image = [UIImage imageNamed:@"Joystick_Gyro_RETINA.png"];
        
        rudderLockButton.center       = leftHandedRudderLockButtonCenter;
        throttleUpButton.center       = leftHandedThrottleUpButtonCenter;
        throttleDownButton.center     = leftHandedThrottleDownButtonCenter;
        upIndicatorImageView.center   = leftHandedUpIndicatorImageViewCenter;
        downIndicatorImageView.center = leftHandedDownIndicatorImageViewCenter; 
    }
    else{
        joystickLeftThumbImageView.image = [UIImage imageNamed:@"Joystick_Gyro_RETINA.png"];
        joystickRightThumbImageView.image = [UIImage imageNamed:@"Joystick_Manuel_RETINA.png"];
        
        rudderLockButton.center       = rudderLockButtonCenter;
        throttleUpButton.center       = throttleUpButtonCenter;
        throttleDownButton.center     = throttleDownButtonCenter;
        upIndicatorImageView.center   = upIndicatorImageViewCenter;
        downIndicatorImageView.center = downIndicatorImageViewCenter; 
    }
    
    [self updateJoysticksForAccModeChanged];
}

- (void)settingsMenuViewController:(SettingsMenuViewController *)ctrl accModeValueDidChange:(BOOL)enabled{
    CMMotionManager *motionManager = [[BasicInfoManager sharedManager] motionManager];
    
    if(motionManager.gyroAvailable == 0 && motionManager.accelerometerAvailable == 1){
        accModeEnabled = enabled;
        //Accelero ok
    } else if (motionManager.deviceMotionAvailable == 1){
        accModeEnabled = enabled;
        //Accelero + gyro ok
    } else {
        //Not gyro and not accelero
        accModeEnabled = FALSE;
    }
    
    [self updateJoysticksForAccModeChanged];
}

- (void)settingsMenuViewController:(SettingsMenuViewController *)ctrl beginnerModeValueDidChange:(BOOL)enabled{
    
}

- (void)settingsMenuViewController:(SettingsMenuViewController *)ctrl headfreeModeValueDidChange:(BOOL)enabled{
    if (_settings.isHeadFreeMode) {
        [_aux1Channel setValue:1];
    }
    else{
        [_aux1Channel setValue:-1];
    }
}

- (void)settingsMenuViewController:(SettingsMenuViewController *)ctrl ppmPolarityReversed:(BOOL)enabled{
    [self stopTransmission];
    [self startTransmission];
}

#pragma mark SettingsMenuViewControllerDelegate Methods end

-(void)blockJoystickHudForTakingOff{
	NSString *blockViewIdentifier = [NSString stringWithFormat:@"%d",  ViewBlockJoyStickHud];
	
	if([blockViewDict valueForKey:blockViewIdentifier] != nil)
		return;
    
    CGRect blockViewPart1Frame = self.view.frame;
    blockViewPart1Frame.origin.x = 0;
    blockViewPart1Frame.origin.y = 0;
    blockViewPart1Frame.size.width = [[UIScreen mainScreen] bounds].size.height;
    blockViewPart1Frame.size.height = joystickLeftButton.frame.origin.y + joystickLeftButton.frame.size.height;
    
	BlockViewStyle1 *blockViewPart1 = [[BlockViewStyle1 alloc] initWithFrame:blockViewPart1Frame];
	blockViewPart1.backgroundColor = [UIColor colorWithWhite:1 alpha:0];
	blockViewPart1.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
	UIView *blockView = blockViewPart1;
    
	[self.view addSubview:blockView];
	[blockViewDict setValue:blockView forKey:[NSString stringWithFormat:@"%d",  ViewBlockJoyStickHud]];
	
}

- (void)unblockJoystickHudForTakingOff:(BOOL)animated{
	NSString *blockViewIdentifier = [NSString stringWithFormat:@"%d",  ViewBlockJoyStickHud];
	UIView *blockView = [blockViewDict valueForKey:blockViewIdentifier];
	
	if(blockView == nil)
		return;
	
	if (animated == YES) {
		[UIView animateWithDuration:1
						 animations:^{
							 blockView.alpha = 0;
						 } completion:^(BOOL finished){
							 [blockView removeFromSuperview];
							 [blockViewDict removeObjectForKey:blockViewIdentifier];
						 }
		 ];
	}
	else {
		[blockView removeFromSuperview];
		[blockViewDict removeObjectForKey:blockViewIdentifier];
	}
}

-(void)blockJoystickHudForStopping{
	NSString *blockViewIdentifier = [NSString stringWithFormat:@"%d",  ViewBlockJoyStickHud2];
	
	if([blockViewDict valueForKey:blockViewIdentifier] != nil)
		return;
    
    CGRect blockViewPart1Frame = self.view.frame;
    blockViewPart1Frame.origin.x = 0;
    blockViewPart1Frame.origin.y = joystickLeftButton.frame.origin.y;
    blockViewPart1Frame.size.width = [[UIScreen mainScreen] bounds].size.height;
    blockViewPart1Frame.size.height = joystickLeftButton.frame.origin.y + joystickLeftButton.frame.size.height - joystickLeftButton.frame.origin.y;
    
	BlockViewStyle1 *blockViewPart1 = [[BlockViewStyle1 alloc] initWithFrame:blockViewPart1Frame];
	blockViewPart1.backgroundColor = [UIColor colorWithWhite:1 alpha:0];
	blockViewPart1.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
	UIView *blockView = blockViewPart1;
    
    
	[self.view addSubview:blockView];
	[blockViewDict setValue:blockView forKey:[NSString stringWithFormat:@"%d",  ViewBlockJoyStickHud2]];
	
}

- (void)unblockJoystickHudForStopping:(BOOL)animated{
	NSString *blockViewIdentifier = [NSString stringWithFormat:@"%d",  ViewBlockJoyStickHud2];
	UIView *blockView = [blockViewDict valueForKey:blockViewIdentifier];
	
	if(blockView == nil)
		return;
	
	if (animated == YES) {
		[UIView animateWithDuration:1
						 animations:^{
							 blockView.alpha = 0;
						 } completion:^(BOOL finished){
							 [blockView removeFromSuperview];
							 [blockViewDict removeObjectForKey:blockViewIdentifier];
						 }
		 ];
	}
	else {
		[blockView removeFromSuperview];
		[blockViewDict removeObjectForKey:blockViewIdentifier];
	}
}

- (void)updateStatusInfoLabel{
    if(throttleIsLocked){
        if(rudderIsLocked){
            statusInfoLabel.text = getLocalizeString(@"Throttle Rudder Locked");
        }
        else {
            statusInfoLabel.text = getLocalizeString(@"Throttle Locked");
        }
    }
    else {
        if(rudderIsLocked){
            statusInfoLabel.text = getLocalizeString(@"Rudder Locked");
        }
        else {
            statusInfoLabel.text = @"";
        }
    }
}

- (void)updateJoystickCenter{
    rightCenter = CGPointMake(joystickRightInitialPosition.x + (joystickRightBackgroundImageView.frame.size.width / 2), joystickRightInitialPosition.y +  (joystickRightBackgroundImageView.frame.size.height / 2));
    leftCenter = CGPointMake(joystickLeftInitialPosition.x + (joystickLeftBackgroundImageView.frame.size.width / 2), joystickLeftInitialPosition.y +  (joystickLeftBackgroundImageView.frame.size.height / 2));
    
    if(isLeftHanded){
        joystickLeftThumbImageView.center = CGPointMake(leftCenter.x, leftCenter.y - _throttleChannel.value * leftJoyStickOperableRadius);
    }
    else{
        joystickRightThumbImageView.center = CGPointMake(rightCenter.x, rightCenter.y - _throttleChannel.value * rightJoyStickOperableRadius);
    }
}

- (void)updateUI{
    OSDData *osdData = [Transmitter sharedTransmitter].osdData;

    rollValueTextLabel.text = [NSString stringWithFormat:@"%.1f", osdData.angleX];
    pitchValueTextLabel.text = [NSString stringWithFormat:@"%.1f", osdData.angleY];
    headAngleValueTextLabel.text = [NSString stringWithFormat:@"%.1f", osdData.head];
    altValueTextLabel.text = [NSString stringWithFormat:@"%.1f", osdData.altitude];
    
    float energy = 0;
    if (osdData.vBat > 3.5) {
        energy =(osdData.vBat - 3.5) / 0.7;
        
        if (energy > 1) {
            energy = 1;
        }
    }
    else{
        energy = 0;
    }
    
    if (energy < 0.25) {
        vBatValueTextLabel.text = @"low";
        vBatValueTextLabel.textColor = [UIColor redColor];
        //vBatValueTextLabel.hidden = !(vBatValueTextLabel.hidden);
        
    }
    else{
        vBatValueTextLabel.hidden = NO;
        vBatValueTextLabel.text = [NSString stringWithFormat:@"%d%%", (int)(energy * 100)];
        vBatValueTextLabel.textColor = batteryLevelLabel.textColor;
    }
    
    //debugValueTextLabel.text = [[BasicInfoManager sharedManager] debugStr];
    
    [self updateFlightState:flightState];
    
    pitchTrimValueTextLabel.text = [NSString stringWithFormat:@"%d", osdData.pitchTrim];
    rollTrimValueTextLabel.text = [NSString stringWithFormat:@"%d", osdData.rollTrim];
    accZtextLabel.text =[NSString stringWithFormat:@"%d", osdData.absolutedAccZ];
    
    rssiValueLabel.text = [NSString stringWithFormat:@"%.1fdb", [[Transmitter sharedTransmitter] rssi] ];
    
    [osdVC updateUI];
    
    //debugTextView.text = osdData.testStr;
}

- (void)updateRSSI{
    [[Transmitter sharedTransmitter] updateRSSI];
}

- (void)checkTransmitterState{
    NSLog(@"checkTransmitterState");
    
    TransmitterState inputState = [[Transmitter sharedTransmitter] inputState];
    TransmitterState outputState = [[Transmitter sharedTransmitter] outputState];
    
    if ((inputState == TransmitterStateOk) && (outputState == TransmitterStateOk)) {
        warningLabel.text = getLocalizeString(@"connected");
        [warningLabel setTextColor:[batteryLevelLabel textColor]];
        warningView.hidden = YES;
    }
    else if((inputState == TransmitterStateOk) && (outputState != TransmitterStateOk)){
       // warningLabel.text = @"Can‘t to send data to WiFi Module, please check the connection is OK.";
        OSDData *osdData = osdVC.osdData;
        osdData.angleX = 0.0f;
        osdData.angleY = 0.0f;
        
        osdData.vBat = 3.3f;
        
        warningLabel.text = getLocalizeString(@"not connected");
        [warningLabel setTextColor:[UIColor redColor]];
        warningView.hidden = NO;
        
    }
    else if((inputState != TransmitterStateOk) && (outputState == TransmitterStateOk)){
        //warningLabel.text = @"Can't get data from WiFi modual, please check the connection is OK.";
       // OSDData *osdData = [Transmitter sharedTransmitter].osdData;
        
    }
    else if((inputState == TransmitterStateOk) && (outputState != TransmitterStateOk)){
        // warningLabel.text = @"Can‘t to send data to WiFi Module, please check the connection is OK.";
        OSDData *osdData = osdVC.osdData;
        osdData.angleX = 0.0f;
        osdData.angleY = 0.0f;
        
        osdData.vBat = 3.3f;
        
        warningLabel.text = getLocalizeString(@"not connected");
        [warningLabel setTextColor:[UIColor redColor]];
        warningView.hidden = NO;
    }
    else {
        OSDData *osdData = osdVC.osdData;
        osdData.angleX = 0.0f;
        osdData.angleY = 0.0f;
        
        osdData.vBat = 3.3f;
        
        warningLabel.text = @"not connected";
        [warningLabel setTextColor:[UIColor redColor]];
        warningView.hidden = NO;
    }
}

- (OSStatus) startTransmission {
    enum PpmPolarity polarity = PPM_POLARITY_POSITIVE;
    
    if(_settings.ppmPolarityIsNegative){
        polarity = PPM_POLARITY_NEGATIVE;
    }
    
    //BOOL s = [[Transmitter sharedTransmitter] startTransmittingPpm];
    BOOL s = [[Transmitter sharedTransmitter] start];
    
    isTransmitting = s;
    
    return s;
}

- (OSStatus) stopTransmission {
    if (isTransmitting) {
        BOOL s = [[Transmitter sharedTransmitter] stop];
        isTransmitting = !s;
        return !s;
    } else {
        return 0;
    }
}

- (void)dismissSettingsMenuView{
    if(_settingMenuVC.view != nil)
        [_settingMenuVC.view removeFromSuperview];
}

- (void)dismissHelpView{
    if(_helpVC.view != nil){
        [_helpVC.view removeFromSuperview];
        _helpVC = nil;
    }
}

- (void)hideBatteryLevelUI
{
	batteryLevelLabel.hidden = YES;
	batteryImageView.hidden = YES;	
}

- (void)showBatteryLevelUI
{
	batteryLevelLabel.hidden = NO;
	batteryImageView.hidden = NO;
}


- (void)setBattery:(int)percent
{
    static int prevImage = -1;
    static int prevPercent = -1;
    static BOOL wasHidden = NO;
	if(percent < 0 && !wasHidden)
	{
		[self performSelectorOnMainThread:@selector(hideBatteryLevelUI) withObject:nil waitUntilDone:YES];		
        wasHidden = YES;
	}
	else if (percent >= 0)
	{
        if (wasHidden)
        {
            [self performSelectorOnMainThread:@selector(showBatteryLevelUI) withObject:nil waitUntilDone:YES];
            wasHidden = NO;
        }
        int imageNumber = ((percent < 10) ? 0 : (int)((percent / 33.4) + 1));
        if (prevImage != imageNumber)
        {
            UIImage *image = [UIImage imageNamed:[NSString stringWithFormat:@"Btn_Battery_%d_RETINA.png", imageNumber]];
            [batteryImageView performSelectorOnMainThread:@selector(setImage:) withObject:image waitUntilDone:YES];
            prevImage = imageNumber;
        }
        if (prevPercent != percent)
        {
            prevPercent = percent;
            [batteryLevelLabel performSelectorOnMainThread:@selector(setText:) withObject:[NSString stringWithFormat:@"%d%%", percent] waitUntilDone:YES];
        }
	}
}

- (void)refreshJoystickRight
{
	CGRect frame = joystickRightBackgroundImageView.frame;
	frame.origin = joystickRightCurrentPosition;
	joystickRightBackgroundImageView.frame = frame;
}    

- (void)refreshJoystickLeft
{
	CGRect frame = joystickLeftBackgroundImageView.frame;
	frame.origin = joystickLeftCurrentPosition;
	joystickLeftBackgroundImageView.frame = frame;
}

//更新摇杆点（joystickRightThumbImageView或joystickLeftThumbImageView）的位置，point是当前触摸点的位置
- (void)updateVelocity:(CGPoint)point isRight:(BOOL)isRight
{
    static BOOL _runOnce = YES;
    static float leftThumbWidth = 0.0;
    static float rightThumbWidth = 0.0;
    static float leftThumbHeight = 0.0;
    static float rightThumbHeight = 0.0;
    static float leftRadius = 0.0;
    static float rightRadius = 0.0;
    
    if (_runOnce)
    {
        leftThumbWidth = joystickLeftThumbImageView.frame.size.width;
        rightThumbWidth = joystickRightThumbImageView.frame.size.width;
        leftThumbHeight = joystickLeftThumbImageView.frame.size.height;
        rightThumbHeight = joystickRightThumbImageView.frame.size.height;
        leftRadius = joystickLeftBackgroundImageView.frame.size.width / 2.0;
        rightRadius = joystickRightBackgroundImageView.frame.size.width / 2.0;
        _runOnce = NO;
    }
    
	CGPoint nextpoint = CGPointMake(point.x, point.y);
	CGPoint center = (isRight ? rightCenter : leftCenter);
	UIImageView *thumbImage = (isRight ? joystickRightThumbImageView : joystickLeftThumbImageView);
	
	float dx = nextpoint.x - center.x;
	float dy = nextpoint.y - center.y;
    
    float thumb_radius = isRight ? rightJoyStickOperableRadius : leftJoyStickOperableRadius;
	
    if(fabsf(dx) > thumb_radius){
        if (dx > 0) {
            nextpoint.x = center.x + rightJoyStickOperableRadius;
        }
        else {
            nextpoint.x = center.x - rightJoyStickOperableRadius;
        }
    }
    
    if(fabsf(dy) > thumb_radius){
        if(dy > 0){
            nextpoint.y = center.y + rightJoyStickOperableRadius;
        }
        else {
             nextpoint.y = center.y - rightJoyStickOperableRadius;
        }
    }

	CGRect frame = thumbImage.frame;
	frame.origin.x = nextpoint.x - (thumbImage.frame.size.width / 2);
	frame.origin.y = nextpoint.y - (thumbImage.frame.size.height / 2);	
	thumbImage.frame = frame;
}

- (void)updateThrottleValueLabel{
    float takeOffValue = clip(-1 + _settings.takeOffThrottle * 2 + _throttleChannel.trimValue, -1.0, 1.0); 
    
    if (_throttleChannel.isReversing) {
        takeOffValue = -takeOffValue;
    }
    
    throttleValueLabel.text = [NSString stringWithFormat:@"%d", (int)(1500 + 500 * _throttleChannel.value)];
}


- (void)setSwitchButton:(UIButton *)switchButton withValue:(BOOL)active
{
    if (active)
    {
        switchButton.tag = SWITCH_BUTTON_CHECKED;
        [switchButton setImage:[UIImage imageNamed:@"Btn_ON.png"] forState:UIControlStateNormal];
    }
    else
    {
        switchButton.tag = SWITCH_BUTTON_UNCHECKED;
        [switchButton setImage:[UIImage imageNamed:@"Btn_OFF.png"] forState:UIControlStateNormal];
    }
}

- (void)toggleSwitchButton:(UIButton *)switchButton
{
    [self setSwitchButton:switchButton withValue:(SWITCH_BUTTON_UNCHECKED == switchButton.tag) ? YES : NO];
}


- (IBAction)switchButtonClick:(id)sender {
    [self toggleSwitchButton:sender];
    
    if(sender == altHoldSwitchButton){
        _settings.isAltHoldMode = (SWITCH_BUTTON_CHECKED == [sender tag]) ? YES : NO;
        [_settings save];
        
        if(_settings.isAltHoldMode){
            [_aux2Channel setValue:1];
        }
        else{
            [_aux2Channel setValue:-1];
        }
    }
}

- (IBAction)joystickButtonDidTouchDown:(id)sender forEvent:(UIEvent *)event {
    UITouch *touch = [[event touchesForView:sender] anyObject];
	CGPoint current_location = [touch locationInView:self.view];
    static CGPoint previous_location;
    
    previous_location = current_location;
    
	if(sender == joystickRightButton)
	{
        static uint64_t right_press_previous_time = 0;
        if(right_press_previous_time == 0) right_press_previous_time = mach_absolute_time();
        
        uint64_t current_time = mach_absolute_time();
        static mach_timebase_info_data_t sRightPressTimebaseInfo;
        uint64_t elapsedNano;
        float dt = 0;
        
        //dt calculus function of real elapsed time
        if(sRightPressTimebaseInfo.denom == 0) (void) mach_timebase_info(&sRightPressTimebaseInfo);
        elapsedNano = (current_time-right_press_previous_time)*(sRightPressTimebaseInfo.numer / sRightPressTimebaseInfo.denom);
        dt = elapsedNano/1000000000.0;
        
        right_press_previous_time = current_time;
        
        if(dt > 0.1 && dt < 0.3){
            if (_settings.isBeginnerMode) {
                if(_throttleChannel.value + kThrottleFineTuningStep > 1 + (kBeginnerThrottleChannelRatio - 1)){
                    _throttleChannel.value = 1;
                }
                else {
                    _throttleChannel.value += kThrottleFineTuningStep;
                }
            }
            else{
                if(_throttleChannel.value + kThrottleFineTuningStep > 1){
                    _throttleChannel.value = 1;
                }
                else {
                    _throttleChannel.value += kThrottleFineTuningStep;
                }
            }
            
            [self updateJoystickCenter];
        }
        
		buttonRightPressed = YES;

		joystickRightBackgroundImageView.alpha = joystickRightThumbImageView.alpha = 1.0;
        
        joystickRightCurrentPosition.x = current_location.x - (joystickRightBackgroundImageView.frame.size.width / 2);
        
        CGPoint thumbCurrentLocation = CGPointZero;
        
        if(isLeftHanded){
            joystickRightCurrentPosition.y = current_location.y - (joystickRightBackgroundImageView.frame.size.height / 2);
            
            [self refreshJoystickRight];
            
            //摇杆中心点
            rightCenter = CGPointMake(joystickRightBackgroundImageView.frame.origin.x + (joystickRightBackgroundImageView.frame.size.width / 2), joystickRightBackgroundImageView.frame.origin.y + (joystickRightBackgroundImageView.frame.size.height / 2));
            
            thumbCurrentLocation = rightCenter;
        }
        else{
            float throttleValue = [_throttleChannel value];
            
            //NSLog(@"throttle value:%f", throttleValue);

            joystickRightCurrentPosition.y = current_location.y - (joystickRightBackgroundImageView.frame.size.height / 2) + throttleValue * rightJoyStickOperableRadius;
            
            [self refreshJoystickRight];
            
            //摇杆中心点
            rightCenter = CGPointMake(joystickRightBackgroundImageView.frame.origin.x + (joystickRightBackgroundImageView.frame.size.width / 2), joystickRightBackgroundImageView.frame.origin.y + (joystickRightBackgroundImageView.frame.size.height / 2));
            
            thumbCurrentLocation = CGPointMake(rightCenter.x, current_location.y);
        }
        
        //更新摇杆点（joystickRightThumbImageView或joystickLeftThumbImageView）的位置
        [self updateVelocity:thumbCurrentLocation isRight:YES];
	}
	else if(sender == joystickLeftButton)
	{
        static uint64_t left_press_previous_time = 0;
        if(left_press_previous_time == 0) left_press_previous_time = mach_absolute_time();
        
        uint64_t current_time = mach_absolute_time();
        static mach_timebase_info_data_t sLeftPressTimebaseInfo;
        uint64_t elapsedNano;
        float dt = 0;
        
        //dt calculus function of real elapsed time
        if(sLeftPressTimebaseInfo.denom == 0) (void) mach_timebase_info(&sLeftPressTimebaseInfo);
        elapsedNano = (current_time-left_press_previous_time)*(sLeftPressTimebaseInfo.numer / sLeftPressTimebaseInfo.denom);
        dt = elapsedNano/1000000000.0;
        
        left_press_previous_time = current_time;
        
        if(dt > 0.1 && dt < 0.3){
            if(_throttleChannel.value - kThrottleFineTuningStep < -1){
                _throttleChannel.value = -1;
            }
            else {
                _throttleChannel.value -= kThrottleFineTuningStep;
            }
            [self updateJoystickCenter];
        }
        
		buttonLeftPressed = YES;
        
        joystickLeftBackgroundImageView.alpha = joystickLeftThumbImageView.alpha = 1.0;
		
		joystickLeftCurrentPosition.x = current_location.x - (joystickLeftBackgroundImageView.frame.size.width / 2);
        
        CGPoint thumbCurrentLocation = CGPointZero;
        
        if(isLeftHanded){
            float throttleValue = [_throttleChannel value];
            
            joystickLeftCurrentPosition.y = current_location.y - (joystickLeftBackgroundImageView.frame.size.height / 2) + throttleValue * leftJoyStickOperableRadius;
            
            [self refreshJoystickLeft];
            
            //摇杆中心点
            leftCenter = CGPointMake(joystickLeftBackgroundImageView.frame.origin.x + (joystickLeftBackgroundImageView.frame.size.width / 2),
                                     joystickLeftBackgroundImageView.frame.origin.y + (joystickLeftBackgroundImageView.frame.size.height / 2));
            
            thumbCurrentLocation = CGPointMake(leftCenter.x, current_location.y);
        }
        else{
            joystickLeftCurrentPosition.y = current_location.y - (joystickLeftBackgroundImageView.frame.size.height / 2);
            
            [self refreshJoystickLeft];
            
            //摇杆中心点
            leftCenter = CGPointMake(joystickLeftBackgroundImageView.frame.origin.x + (joystickLeftBackgroundImageView.frame.size.width / 2), joystickLeftBackgroundImageView.frame.origin.y + (joystickLeftBackgroundImageView.frame.size.height / 2));
            
            thumbCurrentLocation = leftCenter;
        }

		[self updateVelocity:thumbCurrentLocation isRight:NO];
	}
    
    
    
    if (accModeEnabled) {
        if (isLeftHanded) {
            if(sender == joystickRightButton){
                accModeReady = YES;
            }
        }
        else{
            if(sender == joystickLeftButton){
                accModeReady = YES;
            }
        }
    }
    
    if(accModeEnabled && accModeReady)
    {
        // Start only if the first touch is within the pad's boundaries.
        // Allow touches to be tracked outside of the pad as long as the
        // screen continues to be pressed.
        CMMotionManager *motionManager = [[BasicInfoManager sharedManager] motionManager];
        CMAcceleration current_acceleration;
        float phi, theta;
        
        //Get ACCELERO values
        if(motionManager.gyroAvailable == 0 && motionManager.accelerometerAvailable == 1){
            //Only accelerometer (iphone 3GS)
            current_acceleration.x = motionManager.accelerometerData.acceleration.x;
            current_acceleration.y = motionManager.accelerometerData.acceleration.y;
            current_acceleration.z = motionManager.accelerometerData.acceleration.z;
        } else if (motionManager.deviceMotionAvailable == 1){
            //Accelerometer + gyro (iphone 4)
            current_acceleration.x = motionManager.deviceMotion.gravity.x + motionManager.deviceMotion.userAcceleration.x;
            current_acceleration.y = motionManager.deviceMotion.gravity.y + motionManager.deviceMotion.userAcceleration.y;
            current_acceleration.z = motionManager.deviceMotion.gravity.z + motionManager.deviceMotion.userAcceleration.z;
        }
        
        theta = atan2f(current_acceleration.x,sqrtf(current_acceleration.y*current_acceleration.y+current_acceleration.z*current_acceleration.z));
        phi = -atan2f(current_acceleration.y,sqrtf(current_acceleration.x*current_acceleration.x+current_acceleration.z*current_acceleration.z));
        
        //NSLog(@"Repere changed    ref_phi = %*.2f and ref_theta = %*.2f",4,phi * 180/PI,4,theta * 180/PI);
        
        [self setAcceleroRotationWithPhi:phi withTheta:theta withPsi:0];
    }
}

- (IBAction)josystickButtonDidTouchUp:(id)sender forEvent:(UIEvent *)event {
	if(sender == joystickRightButton)
	{
		buttonRightPressed = NO;

		joystickRightCurrentPosition = joystickRightInitialPosition;
		joystickRightBackgroundImageView.alpha = joystickRightThumbImageView.alpha = joystickAlpha;
		
		[self refreshJoystickRight];
        
        if (isLeftHanded) {
            [_aileronChannel setValue:0.0];
            [_elevatorChannel setValue:0.0];
            
            rightCenter = CGPointMake(joystickRightBackgroundImageView.frame.origin.x + (joystickRightBackgroundImageView.frame.size.width / 2), joystickRightBackgroundImageView.frame.origin.y + (joystickRightBackgroundImageView.frame.size.height / 2));
            
            accModeReady = NO;
            
            if(accModeEnabled)
            {
                [self setAcceleroRotationWithPhi:0.0 withTheta:0.0 withPsi:0.0];
            }
        }
        else{
            [_rudderChannel setValue:0.0];
            
            float throttleValue = [_throttleChannel value];
            
            //[self setAltHoldModeIfNeeds:throttleValue];
            
            rightCenter = CGPointMake(joystickRightBackgroundImageView.frame.origin.x + (joystickRightBackgroundImageView.frame.size.width / 2), 
                                      joystickRightBackgroundImageView.frame.origin.y + (joystickRightBackgroundImageView.frame.size.height / 2) - throttleValue * rightJoyStickOperableRadius);
            
            
        }

		[self updateVelocity:rightCenter isRight:YES];
	}
	else if(sender == joystickLeftButton)
	{
		buttonLeftPressed = NO;

		joystickLeftCurrentPosition = joystickLeftInitialPosition;
		joystickLeftBackgroundImageView.alpha = joystickLeftThumbImageView.alpha = joystickAlpha;
		
		[self refreshJoystickLeft];
        
        if (isLeftHanded) {
            [_rudderChannel setValue:0.0];
            
            float throttleValue = [_throttleChannel value];
            
            //[self setAltHoldModeIfNeeds:throttleValue];
            
            leftCenter = CGPointMake(joystickLeftBackgroundImageView.frame.origin.x + (joystickLeftBackgroundImageView.frame.size.width / 2), 
                                      joystickLeftBackgroundImageView.frame.origin.y + (joystickLeftBackgroundImageView.frame.size.height / 2) - throttleValue * rightJoyStickOperableRadius);
        }
        else{
            [_aileronChannel setValue:0.0];
            [_elevatorChannel setValue:0.0];
            
            leftCenter = CGPointMake(joystickLeftBackgroundImageView.frame.origin.x + (joystickLeftBackgroundImageView.frame.size.width / 2), joystickLeftBackgroundImageView.frame.origin.y + (joystickLeftBackgroundImageView.frame.size.height / 2));
            
            accModeReady = NO;
            
            if(accModeEnabled)
            {
                [self setAcceleroRotationWithPhi:0.0 withTheta:0.0 withPsi:0.0];
            }

        }
		
		[self updateVelocity:leftCenter isRight:NO];
	}
}

- (void)setAltHoldModeIfNeeds:(float)throttleValue{
    float scale =  throttleValue;
    
    if (scale > 1) {
        scale = 1;
    }
    else if(scale < -1){
        scale = -1;
    }
    
    int pulseLen =  1500 + 500 * scale;
    
    if(pulseLen >= 1150 && pulseLen <= 1750) {
        if ((((int)[ _aux2Channel value]) != 1)) {
            [_aux2Channel setValue:1];
        }
        
        if (((int)[_aux4Channel value]) != -1) {
            [_aux4Channel setValue:-1];
        }
    }
    else{
        if ((((int)[ _aux2Channel value]) != -1)) {
            [_aux2Channel setValue:-1];
        }
    }
}

- (void)setAltHoldMode:(BOOL)isAltHoldMode{
    if(isAltHoldMode) {
        if ((((int)[ _aux2Channel value]) != 1)) {
            [_aux2Channel setValue:1];
        }
    }
    else{
        if ((((int)[ _aux2Channel value]) != -1)) {
            [_aux2Channel setValue:-1];
        }
    }
}

- (IBAction)joystickButtonDidDrag:(id)sender forEvent:(UIEvent *)event {
    BOOL _runOnce = YES;
    static float rightBackgoundWidth = 0.0;
    static float rightBackgoundHeight = 0.0;
    static float leftBackgoundWidth = 0.0;
    static float leftBackgoundHeight = 0.0;
    if (_runOnce)
    {
        rightBackgoundWidth = joystickRightBackgroundImageView.frame.size.width;
        rightBackgoundHeight = joystickRightBackgroundImageView.frame.size.height;
        leftBackgoundWidth = joystickLeftBackgroundImageView.frame.size.width;
        leftBackgoundHeight = joystickLeftBackgroundImageView.frame.size.height;
        _runOnce = NO;
    }
    
	UITouch *touch = [[event touchesForView:sender] anyObject];
	CGPoint point = [touch locationInView:self.view];
    
    float aileronElevatorValidBandRatio = 0.5 - _settings.aileronDeadBand / 2.0;
    
    float rudderValidBandRatio = 0.5 - _settings.rudderDeadBand / 2.0;
	
	if(sender == joystickRightButton && buttonRightPressed)
	{
        float rightJoystickXInput, rightJoystickYInput; 
        
        float rightJoystickXValidBand;  //右边摇杆x轴的无效区
        float rightJoystickYValidBand;  //右边摇杆y轴的无效区
        
        if(isLeftHanded){
            rightJoystickXValidBand = aileronElevatorValidBandRatio; //X轴操作是Aileron
            rightJoystickYValidBand = aileronElevatorValidBandRatio; //Y轴操作是Elevator
        }
        else{
            rightJoystickXValidBand = rudderValidBandRatio;    
            rightJoystickYValidBand = 0.5;   //Y轴操作是油门
        }
        
        if(!isLeftHanded && rudderIsLocked){  
            rightJoystickXInput = 0.0;  
        }
        //左右操作 (controlRatio * rightBackgoundWidth)是控制的有效区域，所以((rightBackgoundWidth / 2) - (controlRatio * rightBackgoundWidth))就是盲区了
        else if((rightCenter.x - point.x) > ((rightBackgoundWidth / 2) - (rightJoystickXValidBand * rightBackgoundWidth)))   
        {
            float percent = ((rightCenter.x - point.x) - ((rightBackgoundWidth / 2) - (rightJoystickXValidBand * rightBackgoundWidth))) / ((rightJoystickXValidBand * rightBackgoundWidth));
            if(percent > 1.0)
                percent = 1.0;
            
            rightJoystickXInput = -percent;
        }
        else if((point.x - rightCenter.x) > ((rightBackgoundWidth / 2) - (rightJoystickXValidBand * rightBackgoundWidth)))
        {
            float percent = ((point.x - rightCenter.x) - ((rightBackgoundWidth / 2) - (rightJoystickXValidBand * rightBackgoundWidth))) / ((rightJoystickXValidBand * rightBackgoundWidth));
            if(percent > 1.0)
                percent = 1.0;
            
            rightJoystickXInput = percent;
        }
        else
        {
            rightJoystickXInput = 0.0;
        }
        
        //NSLog(@"right x input:%.3f",rightJoystickXInput);
        
        if (isLeftHanded) {
            if (accModeEnabled == NO) {
                if (_settings.isBeginnerMode) {
                    [_aileronChannel setValue:rightJoystickXInput * kBeginnerAileronChannelRatio];
                }
                else{
                    [_aileronChannel setValue:rightJoystickXInput];
                }
            }
        }
        else {
            if(_settings.isBeginnerMode){
                [_rudderChannel setValue:rightJoystickXInput * kBeginnerRudderChannelRatio];
            }
            else{
                [_rudderChannel setValue:rightJoystickXInput];
            }
        }
        
        if(throttleIsLocked && !isLeftHanded){
            rightJoystickYInput = _throttleChannel.value;
        }
        //上下操作
        else if((point.y - rightCenter.y) > ((rightBackgoundHeight / 2) - (rightJoystickYValidBand * rightBackgoundHeight)))
        {
            float percent = ((point.y - rightCenter.y) - ((rightBackgoundHeight / 2) - (rightJoystickYValidBand * rightBackgoundHeight))) / ((rightJoystickYValidBand * rightBackgoundHeight));
            if(percent > 1.0)
                percent = 1.0;
            
            rightJoystickYInput = -percent;
            
        }
        else if((rightCenter.y - point.y) > ((rightBackgoundHeight / 2) - (rightJoystickYValidBand * rightBackgoundHeight)))
        {
            float percent = ((rightCenter.y - point.y) - ((rightBackgoundHeight / 2) - (rightJoystickYValidBand * rightBackgoundHeight))) / ((rightJoystickYValidBand * rightBackgoundHeight));
            if(percent > 1.0)
                percent = 1.0;
            
            rightJoystickYInput = percent;
        }
        else
        {
            rightJoystickYInput = 0.0;
        }
        
        //NSLog(@"right y input:%.3f",rightJoystickYInput);
        
        if (isLeftHanded) {
            if (accModeEnabled == NO) {
                if (_settings.isBeginnerMode) {
                    [_elevatorChannel setValue:rightJoystickYInput * kBeginnerElevatorChannelRatio];
                }
                else{
                    [_elevatorChannel setValue:rightJoystickYInput];
                }
            }
        }
        else {
            [self setAltHoldMode:NO];
            
            if (_settings.isBeginnerMode) {
                [_throttleChannel setValue:(kBeginnerThrottleChannelRatio - 1) + rightJoystickYInput * kBeginnerThrottleChannelRatio];
            }
            else{
                [_throttleChannel setValue:rightJoystickYInput];
            }
            
            [self updateThrottleValueLabel];
        }
	}
	else if(sender == joystickLeftButton
            && buttonLeftPressed)
	{
        float leftJoystickXInput, leftJoystickYInput;
        
        float leftJoystickXValidBand;  //右边摇杆x轴的无效区
        float leftJoystickYValidBand;  //右边摇杆y轴的无效区
        
        if(isLeftHanded){
            leftJoystickXValidBand = rudderValidBandRatio;    
            leftJoystickYValidBand = 0.5;   //Y轴操作是油门
        }
        else{
            leftJoystickXValidBand = aileronElevatorValidBandRatio; //X轴操作是Aileron
            leftJoystickYValidBand = aileronElevatorValidBandRatio; //Y轴操作是Elevator
        }
        
        if(isLeftHanded && rudderIsLocked){
            leftJoystickXInput = 0.0;
        }
		else if((leftCenter.x - point.x) > ((leftBackgoundWidth / 2) - (leftJoystickXValidBand * leftBackgoundWidth)))
		{
			float percent = ((leftCenter.x - point.x) - ((leftBackgoundWidth / 2) - (leftJoystickXValidBand * leftBackgoundWidth))) / ((leftJoystickXValidBand * leftBackgoundWidth));
			if(percent > 1.0)
				percent = 1.0;
            
            leftJoystickXInput = -percent;
            
		}
		else if((point.x - leftCenter.x) > ((leftBackgoundWidth / 2) - (leftJoystickXValidBand * leftBackgoundWidth)))
		{
			float percent = ((point.x - leftCenter.x) - ((leftBackgoundWidth / 2) - (leftJoystickXValidBand * leftBackgoundWidth))) / ((leftJoystickXValidBand * leftBackgoundWidth));
			if(percent > 1.0)
				percent = 1.0;

            leftJoystickXInput = percent;
		}
		else
		{
            leftJoystickXInput = 0.0;
		}	
        
       //NSLog(@"left x input:%.3f",leftJoystickXInput);
		
        if(isLeftHanded){
            if(_settings.isBeginnerMode){
                [_rudderChannel setValue:leftJoystickXInput * kBeginnerRudderChannelRatio];
            }else{
                [_rudderChannel setValue:leftJoystickXInput];
            }
        }
        else{
            if (accModeEnabled == NO) {
                if(_settings.isBeginnerMode){
                    [_aileronChannel setValue:leftJoystickXInput * kBeginnerAileronChannelRatio];
                }else{
                    [_aileronChannel setValue:leftJoystickXInput];
                }
            }
        }
        
        if(throttleIsLocked && isLeftHanded){
            leftJoystickYInput = _throttleChannel.value;
        }
		else if((point.y - leftCenter.y) > ((leftBackgoundHeight / 2) - (leftJoystickYValidBand * leftBackgoundHeight)))
		{
			float percent = ((point.y - leftCenter.y) - ((leftBackgoundHeight / 2) - (leftJoystickYValidBand * leftBackgoundHeight))) / ((leftJoystickYValidBand * leftBackgoundHeight));
			if(percent > 1.0)
				percent = 1.0;
            
            leftJoystickYInput = -percent;
		}
		else if((leftCenter.y - point.y) > ((leftBackgoundHeight / 2) - (leftJoystickYValidBand * leftBackgoundHeight)))
		{
			float percent = ((leftCenter.y - point.y) - ((leftBackgoundHeight / 2) - (leftJoystickYValidBand * leftBackgoundHeight))) / ((leftJoystickYValidBand * leftBackgoundHeight));
			if(percent > 1.0)
				percent = 1.0;
            
            leftJoystickYInput = percent;
		}
		else
		{  
            leftJoystickYInput = 0.0;
		}		
        
        //NSLog(@"left y input:%.3f",leftJoystickYInput);
        
        if(isLeftHanded){
            [self setAltHoldMode:NO];
            
            if (_settings.isBeginnerMode) {
                   [_throttleChannel setValue:(kBeginnerThrottleChannelRatio - 1) + leftJoystickYInput * kBeginnerThrottleChannelRatio];
            }
            else{                
                [_throttleChannel setValue:leftJoystickYInput];
            }
            
            [self updateThrottleValueLabel];
        }
        else{
            if (accModeEnabled == NO) {
                if (_settings.isBeginnerMode) {
                    [_elevatorChannel setValue:leftJoystickYInput * kBeginnerElevatorChannelRatio];
                }
                else{
                    [_elevatorChannel setValue:leftJoystickYInput];
                }
            }
        }
	}
    
    BOOL isRight = (sender == joystickRightButton);
    
    
    if (isLeftHanded) {
        if (isRight && buttonRightPressed && accModeEnabled) {
            ;
        }
        else{
            [self updateVelocity:point isRight:isRight];
        }
    }
    else{
        if ((isRight == NO) && buttonLeftPressed && accModeEnabled) {
            ;
        }
        else{
            [self updateVelocity:point isRight:isRight];
        }
    }
    
    
//    if ((isRight && buttonRightPressed) ||
//        (!isRight && buttonLeftPressed))
//    {
//        [self updateVelocity:point isRight:isRight];
//    }
}


- (void)showHelpView{
    _helpVC = nil;
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        _helpVC = [[HelpViewController alloc] initWithNibName:@"HelpViewController" bundle:nil];
    } else {
        if (isIphone5()) {
            _helpVC = [[HelpViewController alloc] initWithNibName:@"HelpViewController_iPhone_tall" bundle:nil];
        }
        else{
            _helpVC = [[HelpViewController alloc] initWithNibName:@"HelpViewController_iPhone" bundle:nil];
        }
    }
    
    [self.view addSubview:_helpVC.view];
}

- (void)showSettingsMenuView{
    _settingMenuVC = nil;
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        _settingMenuVC = [[SettingsMenuViewController alloc] initWithNibName:@"SettingsMenuViewController" bundle:nil settings:_settings];
    } else {
        if (isIphone5()) {
            _settingMenuVC = [[SettingsMenuViewController alloc] initWithNibName:@"SettingsMenuViewController_iPhone_tall" bundle:nil settings:_settings];
        }
        else{
            _settingMenuVC = [[SettingsMenuViewController alloc] initWithNibName:@"SettingsMenuViewController_iPhone" bundle:nil settings:_settings];
        }
    }
    
    _settingMenuVC.delegate = self;
    
    [self.view addSubview:_settingMenuVC.view];
}

- (IBAction)takoffButtonDidTouchDown:(id)sender {
    [self blockJoystickHudForTakingOff];
    
    _aileronChannel.value = 0;
    _elevatorChannel.value = 0;
    _rudderChannel.value = 0;
    
    float takeOffValue = clip(-1 + _settings.takeOffThrottle * 2 + _throttleChannel.trimValue, -1.0, 1.0); 
    
    if (_throttleChannel.isReversing) {
        takeOffValue = -takeOffValue;
    }
    
    _throttleChannel.value = takeOffValue;
    
    [self updateThrottleValueLabel];
    [self updateJoystickCenter];
}

- (IBAction)takeoffButtonDidTouchUp:(id)sender {
    [self unblockJoystickHudForTakingOff:NO];
}

- (IBAction)throttleStopButtonDidTouchDown:(id)sender {
    [self blockJoystickHudForStopping];
    
    _aileronChannel.value = 0;
    _elevatorChannel.value = 0;
    _rudderChannel.value = 0;
    _throttleChannel.value = -1;
    
    [self updateThrottleValueLabel];
    [self updateJoystickCenter];
}

- (IBAction)throttleStopButtonDidTouchUp:(id)sender {
    [self unblockJoystickHudForStopping:NO];
}

- (void)setView:(UIView *)view hidden:(BOOL)hidden{
    //view.h
}

- (IBAction)buttonDidTouchDown:(id)sender {
    if(sender == throttleUpButton){ 
        upIndicatorImageView.hidden = NO;
    }
    else if(sender == throttleDownButton){
        downIndicatorImageView.hidden = NO;
    }
}

- (IBAction)buttonDidDragEnter:(id)sender {
    if(sender == throttleUpButton || sender == throttleDownButton){ 
        [self buttonDidTouchDown:sender];
    }
}

- (IBAction)buttonDidDragExit:(id)sender {
    if(sender == throttleUpButton || sender == throttleDownButton){ 
        [self buttonDidTouchUpOutside:sender];
    }
}

- (IBAction)buttonDidTouchUpInside:(id)sender {
    if(sender == setttingButton){
        [self showSettingsMenuView];
    }
    else if(sender == rudderLockButton){
        rudderIsLocked = !rudderIsLocked;
        
        if(rudderIsLocked){
            if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
                [rudderLockButton setImage:[UIImage imageNamed:@"Switch_On_IPAD.png"] forState:UIControlStateNormal];
            } 
            else {
                [rudderLockButton setImage:[UIImage imageNamed:@"Switch_On_RETINA.png"] forState:UIControlStateNormal];
            }
        }
        else{
            if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
                [rudderLockButton setImage:[UIImage imageNamed:@"Switch_Off_IPAD.png"] forState:UIControlStateNormal];
            } 
            else {
                [rudderLockButton setImage:[UIImage imageNamed:@"Switch_Off_RETINA.png"] forState:UIControlStateNormal];
            }
        }
        
        [self updateStatusInfoLabel];
    }
    else if(sender == throttleUpButton){
        if(_throttleChannel.value + kThrottleFineTuningStep > 1){
            _throttleChannel.value = 1; 
        }
        else {
            _throttleChannel.value += kThrottleFineTuningStep;
        }
        [self updateJoystickCenter];
        
        if(isLeftHanded){
            joystickLeftThumbImageView.center = CGPointMake(joystickLeftThumbImageView.center.x, leftCenter.y - _throttleChannel.value * leftJoyStickOperableRadius);
        }
        else{
            joystickRightThumbImageView.center = CGPointMake(joystickRightThumbImageView.center.x, rightCenter.y - _throttleChannel.value * rightJoyStickOperableRadius);
        }   
        
        upIndicatorImageView.hidden = YES;
        
        [self updateThrottleValueLabel];
    }
    else if(sender == throttleDownButton){
        if(_throttleChannel.value - kThrottleFineTuningStep < -1){
            _throttleChannel.value = -1; 
        }
        else {
            _throttleChannel.value -= kThrottleFineTuningStep;
        }
        [self updateJoystickCenter];
        
        downIndicatorImageView.hidden = YES;
        
        [self updateThrottleValueLabel];
    }
    else if(sender == helpButton){
        [self showHelpView];
    }
}

- (IBAction)buttonDidTouchUpOutside:(id)sender {
    if(sender == throttleUpButton){ 
        upIndicatorImageView.hidden = YES;
    }
    else if(sender == throttleDownButton){
        downIndicatorImageView.hidden = YES;
    }
}

- (IBAction)buttonDidTouchCancel:(id)sender {
    if(sender == throttleUpButton || sender == throttleDownButton){ 
        [self buttonDidTouchUpOutside:sender];
    }
}

- (IBAction)unlockButtonDidTouchUp:(id)sender {
    _aileronChannel.value = 0;
    _elevatorChannel.value = 0;
    _rudderChannel.value = 0;
    _throttleChannel.value = -1;
    
    [self updateThrottleValueLabel];
    [self updateJoystickCenter];
    
    [[Transmitter sharedTransmitter] transmmitSimpleCommand:MSP_ARM];
}

- (IBAction)lockButtonDidTouchUp:(id)sender {
    [[Transmitter sharedTransmitter] transmmitSimpleCommand:MSP_DISARM];
}


- (void)updateDebugTextView{
   // OSDData *osdData = [Transmitter sharedTransmitter].osdData;
}

- (void)flight{

}

- (void)updateDebugTextView2{
    //debugTextView.text = [NSString stringWithFormat:@"%@\n<<******", debugTextView.text];
    
    for (int idx = 0; idx < kAltArrayMaxLen; idx++) {
        //int alt = altArray[idx];
        
       // debugTextView.text = [NSString stringWithFormat:@"%@\n%f", debugTextView.text, altArray[idx]];
    }
    
   // debugTextView.text = [NSString stringWithFormat:@"%@\n******", debugTextView.text];

}

- (void)updateDebugTextViewWithString:(NSString *)str{
    //debugTextView.text = [NSString stringWithFormat:@"%@\n%@", debugTextView.text, str];
}


- (BOOL)checkAltArray{
    if (altArrayVaildLen != kAltArrayMaxLen) {  //数据还没采集足够的多
        return FALSE;
    }
    
    [self performSelectorOnMainThread:@selector(updateDebugTextView2) withObject:nil waitUntilDone:YES];
    

    
    int invalidAltCnt = 0;
    
    for (int idx = 0; idx < kAltArrayMaxLen; idx++) {
        if (25 < altArray[idx] < 150) {
            
        }
        else{
            invalidAltCnt++;
        }
    }
    
    if (invalidAltCnt > 2) {
        [self performSelectorOnMainThread:@selector(updateDebugTextViewWithString:) withObject:@"度范围不对>>" waitUntilDone:YES];
        
        return FALSE;
    }
    /*
    else{
        invalidAltCnt = 0;
        
        for (int idx = 0; idx < kAltArrayMaxLen - 1; idx++) {
            if(fabs(altArray[idx + 1] - altArray[idx]) > 12){
                invalidAltCnt++;
                
                if (fabs(altArray[idx + 1] - altArray[idx]) > 30) {
                    [self performSelectorOnMainThread:@selector(updateDebugTextViewWithString:) withObject:@"值相差不对>>" waitUntilDone:NO];
                    //debugTextView.text = [NSString stringWithFormat:@"%@\n值相差不对>>", debugTextView.text];
                    return FALSE;
                }
            }
            else if(fabs(altArray[idx + 1] - altArray[idx]) == 0){
                invalidAltCnt++;
            }
            else{
                invalidAltCnt--;
            }
        }
        
        if (invalidAltCnt > 2) {
            [self performSelectorOnMainThread:@selector(updateDebugTextViewWithString:) withObject:@"值相差不对>>" waitUntilDone:NO];
            //debugTextView.text = [NSString stringWithFormat:@"%@\n值相差不对>>", debugTextView.text];
            return FALSE;
        }
    }*/
    
    invalidAltCnt = 0;
    
    int sum = 0;
    int average = 0;
    
    for(int idx = 0; idx < kAltArrayMaxLen; idx++){
        sum += altArray[idx];
    }
    
    average = sum / kAltArrayMaxLen;
    
    for(int idx = 0; idx < kAltArrayMaxLen; idx++){
        if(fabs(altArray[idx] - average) > 30){
            invalidAltCnt++;
        }
    }
    
    if (invalidAltCnt > 1) {
        [self performSelectorOnMainThread:@selector(updateDebugTextViewWithString:) withObject:@"平均值不对>>" waitUntilDone:YES];
        //debugTextView.text = [NSString stringWithFormat:@"%@\n值相差不对>>", debugTextView.text];
        return FALSE;
    }

    
    
    [self performSelectorOnMainThread:@selector(updateDebugTextViewWithString:) withObject:@"跨过盲区>>" waitUntilDone:YES];
    //debugTextView.text = [NSString stringWithFormat:@"%@\n跨过盲区>>", debugTextView.text];
    
    return TRUE;
}


- (void)autoTakeOff2{
    OSDData *osdData = [Transmitter sharedTransmitter].osdData;
    
    int accZ = osdData.absolutedAccZ;
    float altitude = osdData.altitude;
    
    NSLog(@">>>***%d", osdData.absolutedAccZ);
    
    if (accZ < -5) {
        checkCnt++;
        
        [self performSelectorOnMainThread:@selector(updateDebugTextView) withObject:nil waitUntilDone:NO];
    }
    
    
#define MAX_ACC_TIME_CNT 30
    if (checkCnt > 0) {  //获得了怠速
        [self performSelectorOnMainThread:@selector(updateDebugTextViewWithString:) withObject:@"获得怠速" waitUntilDone:NO];
        /*
        if (accTimeCnt > MAX_ACC_TIME_CNT) {  //获得怠速之后，自动起飞超时了
            [throttleTimer invalidate];
            [throttleTimer release];
            throttleTimer = nil;
            
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(autoTakeOffTimeOut)  object:nil];
            
            
            [_aux2Channel setValue:-1];
            
            
            autoTakeOffState.text = [NSString stringWithFormat:@"1 %d %d", checkCnt, (int)(1500 + 500 * _throttleChannel.value)];
            
            isAutoTakingOff = NO;
            
            return;
        }*/
        
        if (altArrayVaildLen < kAltArrayMaxLen) {
            altArray[altArrayVaildLen] = altitude;
            altArrayVaildLen++;
        }
        else{
            for (int idx = 0; idx < kAltArrayMaxLen - 1; idx++) {
                altArray[idx] = altArray[idx + 1];
            }
            altArray[kAltArrayMaxLen - 1] = altitude;
            altArrayVaildLen = kAltArrayMaxLen;
            //altArrayVaildLen++;
        }

        
        if([self checkAltArray]){  //越过了盲区
            [throttleTimer invalidate];
            throttleTimer = nil;
            
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(autoTakeOffTimeOut)  object:nil];
            
            [_aux2Channel setValue:1];
            
            autoTakeOffState.text = [NSString stringWithFormat:@"1 %d %d", checkCnt, (int)(1500 + 500 * _throttleChannel.value)];
            
            isAutoTakingOff = NO;
        }
        else{
            [self performSelectorOnMainThread:@selector(updateDebugTextViewWithString:) withObject:@"未跨过盲区" waitUntilDone:NO];
            
            if (_throttleChannel.value < 0.7) {
                if (accZ >= -5) {
                    _throttleChannel.value += (15 / 500.0f);
                }
                else if(accZ < -25){
                    _throttleChannel.value -= (10 / 500.0f);
                }
                
                [self performSelectorOnMainThread:@selector(updateJoystickCenter) withObject:nil waitUntilDone:NO];
            }
            else{

            }
        }
        
        accTimeCnt++;
    }
    else{  //加怠速
        if (_throttleChannel.value < 0.6) {
            if (accZ > -30) {
                _throttleChannel.value += (10 / 500.0f);
                
                [self performSelectorOnMainThread:@selector(updateJoystickCenter) withObject:nil waitUntilDone:NO];
            }
        }
    }
}

- (void)autoTakeOff{
    OSDData *osdData = [Transmitter sharedTransmitter].osdData;
    
    int accZ = osdData.absolutedAccZ;
    //float altitude = osdData.altitude;
    
    
    NSLog(@">>>***%d", osdData.absolutedAccZ);
    
    //if ( (accZ > -50) && (accZ < - 15)) {
         if (accZ < - 5) {
        
        checkCnt++;
             
//             if (_throttleChannel.value < 0.5) {
//                 if (accZ > -30) {
//                     _throttleChannel.value += ( 5 / 500.0f) + (15 * ((29 - fabs(accZ)) / 19.0f));
//                 }
//             }
        
        [self performSelectorOnMainThread:@selector(updateDebugTextView) withObject:nil waitUntilDone:NO];
    }
    /*
    else if(accZ <= -50){
        checkCnt++;
        
     
        if (_throttleChannel.value > -0.8) {
            _throttleChannel.value -= (10 / 500.0f);
            
            [self performSelectorOnMainThread:@selector(updateJoystickCenter) withObject:nil waitUntilDone:NO];
        }
     
    }*/
    
    //if (checkCnt * kCheckDuration > 0.1) {
    
    
//#define MAX_ACC_TIME_CNT 19
    
    if (checkCnt > 0) {
        if (accTimeCnt > MAX_ACC_TIME_CNT) {
            [throttleTimer invalidate];
            throttleTimer = nil;
            
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(autoTakeOffTimeOut)  object:nil];
            
            
            [_aux2Channel setValue:1];
            
            
            autoTakeOffState.text = [NSString stringWithFormat:@"1 %d %d", checkCnt, (int)(1500 + 500 * _throttleChannel.value)];
            
            isAutoTakingOff = NO;
       
        }
        else{
            if (_throttleChannel.value < 0.5) {
                if (accZ > -25) {

                    if (accTimeCnt == 0) {
                        _throttleChannel.value += (25 / 500.0f);
                    }
                    else if(accTimeCnt == 1){
                        _throttleChannel.value += (25 / 500.0f);
                    }
                    else if(accTimeCnt == 2){
                        _throttleChannel.value += (20 / 500.0f);
                    }
                    else if(accTimeCnt == 3){
                        _throttleChannel.value += (20 / 500.0f);
                    }
                    else if(accTimeCnt == 4){
                        _throttleChannel.value += (20 / 500.0f);
                    }
                    else if(accTimeCnt == 5){
                        _throttleChannel.value += (20 / 500.0f);
                    }
                    else if(accTimeCnt == 6){
                        _throttleChannel.value += (20 / 500.0f);
                    }
                    else if(accTimeCnt == 7){
                        _throttleChannel.value += (18 / 500.0f);
                    }
                    else if(accTimeCnt == 8){
                        _throttleChannel.value += (18 / 500.0f);
                    }
                    else if(accTimeCnt == 9){
                        _throttleChannel.value += (18 / 500.0f);
                    }
                    else if(accTimeCnt == 10){
                        _throttleChannel.value += (18 / 500.0f);
                    }
                    
                    else if(accTimeCnt == 11){
                        _throttleChannel.value += (18 / 500.0f);
                    }
                    else if(accTimeCnt == 12){
                        _throttleChannel.value += (18 / 500.0f);
                    }
                    else{
//                        if (30 < altitude < 100) {
//                            [throttleTimer invalidate];
//                            [throttleTimer release];
//                            throttleTimer = nil;
//                            
//                            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(autoTakeOffTimeOut)  object:nil];
//                            
//                            
//                            [_aux2Channel setValue:1];
//                            
//                            
//                            autoTakeOffState.text = [NSString stringWithFormat:@"1 %d %d", checkCnt, (int)(1500 + 500 * _throttleChannel.value)];
//                            
//                            isAutoTakingOff = NO;
//                        }
//                        else
                        if(accTimeCnt == 13){
                            _throttleChannel.value += (18 / 500.0f);
                        }
                        else if(accTimeCnt == 14){
                            _throttleChannel.value += (18 / 500.0f);
                        }
                        else if(accTimeCnt == 15){
                            _throttleChannel.value += (18 / 500.0f);
                        }
                        
                        else if(accTimeCnt == 16){
                            _throttleChannel.value += (15 / 500.0f);
                        }
                        
                        else if(accTimeCnt == 17){
                            _throttleChannel.value += (15 / 500.0f);
                        }
                        
                        else if(accTimeCnt == 18){
                            _throttleChannel.value += (15 / 500.0f);
                        }
                        
                        else if(accTimeCnt == 19){
                            _throttleChannel.value += (15 / 500.0f);
                        }
                    
                                           }
                    
                    [self performSelectorOnMainThread:@selector(updateJoystickCenter) withObject:nil waitUntilDone:NO];
                }
                else{
                    [throttleTimer invalidate];
                    throttleTimer = nil;
                    
                    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(autoTakeOffTimeOut)  object:nil];
                    
                    
                    [_aux2Channel setValue:1];
                    
                    
                    autoTakeOffState.text = [NSString stringWithFormat:@"1 %d %d", checkCnt, (int)(1500 + 500 * _throttleChannel.value)];
                    
                    isAutoTakingOff = NO;
                }
            }
        }
        
        accTimeCnt++;
    }
    else{
        if (_throttleChannel.value < 0.5) {
            if (accZ > -30) {
                _throttleChannel.value += (22 / 500.0f);
                
                [self performSelectorOnMainThread:@selector(updateJoystickCenter) withObject:nil waitUntilDone:NO];
            }
        }
    }
    
    
//    
//    if (checkCnt > 0) {
//        
//        
//        
//        
//        uint64_t current_time = mach_absolute_time();
//        static mach_timebase_info_data_t sRightPressTimebaseInfo;
//        uint64_t elapsedNano;
//        float dt = 0;
//        
//        //dt calculus function of real elapsed time
//        if(sRightPressTimebaseInfo.denom == 0) (void) mach_timebase_info(&sRightPressTimebaseInfo);
//        elapsedNano = (current_time-take_off_start_time)*(sRightPressTimebaseInfo.numer / sRightPressTimebaseInfo.denom);
//        dt = elapsedNano/1000000000.0;
//        
//        if (altitude > 130) {
//            if (dt < 4.5) {  //此altitude是由超声波盲区造成的
//                if (_throttleChannel.value < 0.5) {
//                    if (accZ <= -30) {
//                        return;
//                    }
//                    
//                    _throttleChannel.value += ((4.5 - dt) / 4.5 * 50 / 500.0f);
//                    
//                    [self performSelectorOnMainThread:@selector(updateJoystickCenter) withObject:nil waitUntilDone:NO];
//                }
//            }
//            else{
//                if (_throttleChannel.value > -0.8) {
//                    _throttleChannel.value -= (20 / 500.0f);
//                    
//                    [self performSelectorOnMainThread:@selector(updateJoystickCenter) withObject:nil waitUntilDone:NO];
//                }
//            }
//            
//            
//            return;
//        }
//        else if(altitude < 50){
//            if (_throttleChannel.value < 0.5) {
//                if (accZ <= -30) {
//                    return;
//                }
//                
//                _throttleChannel.value += (20 / 500.0f);
//                
//                [self performSelectorOnMainThread:@selector(updateJoystickCenter) withObject:nil waitUntilDone:NO];
//            }
//        }
//        else{
//            
//            
//            [throttleTimer invalidate];
//            [throttleTimer release];
//            throttleTimer = nil;
//            
//            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(autoTakeOffTimeOut)  object:nil];
//        
//            
//            [_aux2Channel setValue:1];
//            
//            
//            
//            
//            autoTakeOffState.text = [NSString stringWithFormat:@"1 %d %d", checkCnt, (int)(1500 + 500 * _throttleChannel.value)];
//            
//            isAutoTakingOff = NO;
//        }
//        //}
//    }
//    else{
//        if (_throttleChannel.value < 0.5) {
//            if (accZ <= -30) {
//                return;
//            }
//            
//            _throttleChannel.value += (22 / 500.0f);
//            
//            [self performSelectorOnMainThread:@selector(updateJoystickCenter) withObject:nil waitUntilDone:NO];
//        }
//    }
}
//}

- (void)autoTakeOffTimeOut{
    if (isAutoTakingOff) {
        [throttleTimer invalidate];
        throttleTimer = nil;
        isAutoTakingOff = NO;
        [_aux4Channel setValue:-1];
        
        autoTakeOffState.text = [NSString stringWithFormat:@"%d timeout", checkCnt];
        
        [self updateDebugTextViewWithString:@"自动起飞超时，自动起飞失败"];
        //[self lockButtonDidTouchUp:nil];
    }
}


- (void)updateFlightState:(flight_state_t) flightSate_{
    flightState = flightSate_;
    
    switch (flightState) {
        case flight_state_taking_off:
            debugValueTextLabel.text = @"自动起飞中...";
            break;
        case flight_state_angle:
            debugValueTextLabel.text = @"特技模式";
            break;
        case flight_state_horizon:
            debugValueTextLabel.text = @"自稳模式";
            break;
        case flight_state_baro:
            debugValueTextLabel.text = @"气压计定高模式";
            break;
        case flight_state_sonar:
            debugValueTextLabel.text = @"超声波定高模式";
            break;
        case flight_state_headfree:
            debugValueTextLabel.text = @"无头模式";
            break;
        default:
            break;
    }
}

- (IBAction)autoTakeOff:(id)sender {
    if (isAutoTakingOff == NO) {
        
        altArrayVaildLen = 0;
        
        take_off_start_time = mach_absolute_time();
        
        autoTakeOffState.text =  @"0";
        
        checkCnt = 0;
        accTimeCnt = 0;
        [_aux2Channel setValue:-1];
        [_aux4Channel setValue:1];
        
        [self unlockButtonDidTouchUp:nil];
        isAutoTakingOff = YES;
        
        flightState = flight_state_taking_off;
        
        throttleTimer = [NSTimer scheduledTimerWithTimeInterval:kCheckDuration target:self selector:@selector(autoTakeOff2) userInfo:nil repeats:YES];
        [self performSelector:@selector(autoTakeOffTimeOut) withObject:nil afterDelay:10];
    }
}


- (void) setAcceleroRotationWithPhi:(float)phi withTheta:(float)theta withPsi:(float)psi
{
	accelero_rotation[0][0] = cosf(psi)*cosf(theta);
	accelero_rotation[0][1] = -sinf(psi)*cosf(phi) + cosf(psi)*sinf(theta)*sinf(phi);
	accelero_rotation[0][2] = sinf(psi)*sinf(phi) + cosf(psi)*sinf(theta)*cosf(phi);
	accelero_rotation[1][0] = sinf(psi)*cosf(theta);
	accelero_rotation[1][1] = cosf(psi)*cosf(phi) + sinf(psi)*sinf(theta)*sinf(phi);
	accelero_rotation[1][2] = -cosf(psi)*sinf(phi) + sinf(psi)*sinf(theta)*cosf(phi);
	accelero_rotation[2][0] = -sinf(theta);
	accelero_rotation[2][1] = cosf(theta)*sinf(phi);
	accelero_rotation[2][2] = cosf(theta)*cosf(phi);
    
#ifdef WRITE_DEBUG_ACCELERO
	NSLog(@"Accelero rotation matrix changed :");
	NSLog(@"%0.1f %0.1f %0.1f", accelero_rotation[0][0], accelero_rotation[0][1], accelero_rotation[0][2]);
	NSLog(@"%0.1f %0.1f %0.1f", accelero_rotation[1][0], accelero_rotation[1][1], accelero_rotation[1][2]);
	NSLog(@"%0.1f %0.1f %0.1f", accelero_rotation[2][0], accelero_rotation[2][1], accelero_rotation[2][2]);
#endif
}


- (void)motionDataHandler
{
    static uint64_t previous_time = 0;
    if(previous_time == 0) previous_time = mach_absolute_time();
    
    uint64_t current_time = mach_absolute_time();
    static mach_timebase_info_data_t sTimebaseInfo;
    uint64_t elapsedNano;
    float dt = 0;
    
    static float highPassFilterX = 0.0, highPassFilterY = 0.0, highPassFilterZ = 0.0;
    
    CMAcceleration current_acceleration = { 0.0, 0.0, 0.0 };
    static CMAcceleration last_acceleration = { 0.0, 0.0, 0.0 };
    
    static bool first_time_accelero = TRUE;
    static bool first_time_gyro = TRUE;
    
    static float angle_gyro_x, angle_gyro_y, angle_gyro_z;
    float current_angular_rate_x, current_angular_rate_y, current_angular_rate_z;
    
    static float hpf_gyro_x, hpf_gyro_y, hpf_gyro_z;
    static float last_angle_gyro_x, last_angle_gyro_y, last_angle_gyro_z;
    
    float phi, theta = 0.0;
    
    //dt calculus function of real elapsed time
    if(sTimebaseInfo.denom == 0) (void) mach_timebase_info(&sTimebaseInfo);
    elapsedNano = (current_time-previous_time)*(sTimebaseInfo.numer / sTimebaseInfo.denom);
    previous_time = current_time;
    dt = elapsedNano/1000000000.0;
    
    //Execute this part of code only on the joystick button pressed
    CMMotionManager *motionManager = [[BasicInfoManager sharedManager] motionManager];
    
    //Get ACCELERO values
    if(motionManager.gyroAvailable == 0 && motionManager.accelerometerAvailable == 1)
    {
        //Only accelerometer (iphone 3GS)
        current_acceleration.x = motionManager.accelerometerData.acceleration.x;
        current_acceleration.y = motionManager.accelerometerData.acceleration.y;
        current_acceleration.z = motionManager.accelerometerData.acceleration.z;
    }
    else if (motionManager.deviceMotionAvailable == 1)
    {
        //Accelerometer + gyro (iphone 4)
        current_acceleration.x = motionManager.deviceMotion.gravity.x + motionManager.deviceMotion.userAcceleration.x;
        current_acceleration.y = motionManager.deviceMotion.gravity.y + motionManager.deviceMotion.userAcceleration.y;
        current_acceleration.z = motionManager.deviceMotion.gravity.z + motionManager.deviceMotion.userAcceleration.z;
    }
    
    //NSLog(@"Before Shake %f %f %f",current_acceleration.x, current_acceleration.y, current_acceleration.z);
    
    if( isnan(current_acceleration.x) || isnan(current_acceleration.y) || isnan(current_acceleration.z)
       || fabs(current_acceleration.x) > 10 || fabs(current_acceleration.y) > 10 || fabs(current_acceleration.z)>10)
    {
        static uint32_t count = 0;
        static BOOL popUpWasDisplayed = NO;
        NSLog (@"Accelero errors : %f, %f, %f (count = %d)", current_acceleration.x, current_acceleration.y, current_acceleration.z, count);
        NSLog (@"Accelero raw : %f/%f, %f/%f, %f/%f", motionManager.deviceMotion.gravity.x, motionManager.deviceMotion.userAcceleration.x, motionManager.deviceMotion.gravity.y, motionManager.deviceMotion.userAcceleration.y, motionManager.deviceMotion.gravity.z, motionManager.deviceMotion.userAcceleration.z);
        NSLog (@"Attitude : %f / %f / %f", motionManager.deviceMotion.attitude.roll, motionManager.deviceMotion.attitude.pitch, motionManager.deviceMotion.attitude.yaw);
        return;
    }
    
    //INIT accelero variables
    if(first_time_accelero == TRUE)
    {
        first_time_accelero = FALSE;
        last_acceleration.x = current_acceleration.x;
        last_acceleration.y = current_acceleration.y;
        last_acceleration.z = current_acceleration.z;
    }
    
    float highPassFilterConstant = (1.0 / 5.0) / ((1.0 / 40) + (1.0 / 5.0)); // (1.0 / 5.0) / ((1.0 / kAPS) + (1.0 / 5.0));
    
    
    //HPF on the accelero
    highPassFilterX = highPassFilterConstant * (highPassFilterX + current_acceleration.x - last_acceleration.x);
    highPassFilterY = highPassFilterConstant * (highPassFilterY + current_acceleration.y - last_acceleration.y);
    highPassFilterZ = highPassFilterConstant * (highPassFilterZ + current_acceleration.z - last_acceleration.z);
    
    //Save the previous values
    last_acceleration.x = current_acceleration.x;
    last_acceleration.y = current_acceleration.y;
    last_acceleration.z = current_acceleration.z;
    
#define ACCELERO_THRESHOLD          0.2
#define ACCELERO_FASTMOVE_THRESHOLD	1.3
    
    if(fabs(highPassFilterX) > ACCELERO_FASTMOVE_THRESHOLD ||
       fabs(highPassFilterY) > ACCELERO_FASTMOVE_THRESHOLD ||
       fabs(highPassFilterZ) > ACCELERO_FASTMOVE_THRESHOLD){
        ;
    }
    else{
        if(accModeEnabled){
            if(accModeReady == NO){
                [_aileronChannel setValue:0];
                [_elevatorChannel setValue:0];
            }
            else{
                
                
                CMAcceleration current_acceleration_rotate;
                float angle_acc_x;
                float angle_acc_y;
                
                //LPF on the accelero
                current_acceleration.x = 0.9 * last_acceleration.x + 0.1 * current_acceleration.x;
                current_acceleration.y = 0.9 * last_acceleration.y + 0.1 * current_acceleration.y;
                current_acceleration.z = 0.9 * last_acceleration.z + 0.1 * current_acceleration.z;
                
                //Save the previous values
                last_acceleration.x = current_acceleration.x;
                last_acceleration.y = current_acceleration.y;
                last_acceleration.z = current_acceleration.z;
                
                //Rotate the accelerations vectors
                current_acceleration_rotate.x =
                (accelero_rotation[0][0] * current_acceleration.x)
                + (accelero_rotation[0][1] * current_acceleration.y)
                + (accelero_rotation[0][2] * current_acceleration.z);
                current_acceleration_rotate.y =
                (accelero_rotation[1][0] * current_acceleration.x)
                + (accelero_rotation[1][1] * current_acceleration.y)
                + (accelero_rotation[1][2] * current_acceleration.z);
                current_acceleration_rotate.z =
                (accelero_rotation[2][0] * current_acceleration.x)
                + (accelero_rotation[2][1] * current_acceleration.y)
                + (accelero_rotation[2][2] * current_acceleration.z);
                
                //IF sequence to remove the angle jump problem when accelero mesure X angle AND Y angle AND Z change of sign
                if(current_acceleration_rotate.y > -ACCELERO_THRESHOLD && current_acceleration_rotate.y < ACCELERO_THRESHOLD)
                {
                    angle_acc_x = atan2f(current_acceleration_rotate.x,
                                         sign(-current_acceleration_rotate.z)*sqrtf(current_acceleration_rotate.y*current_acceleration_rotate.y+current_acceleration_rotate.z*current_acceleration_rotate.z));
                }
                else
                {
                    angle_acc_x = atan2f(current_acceleration_rotate.x,
                                         sqrtf(current_acceleration_rotate.y*current_acceleration_rotate.y+current_acceleration_rotate.z*current_acceleration_rotate.z));
                }
                
                //IF sequence to remove the angle jump problem when accelero mesure X angle AND Y angle AND Z change of sign
                if(current_acceleration_rotate.x > -ACCELERO_THRESHOLD && current_acceleration_rotate.x < ACCELERO_THRESHOLD)
                {
                    angle_acc_y = atan2f(current_acceleration_rotate.y,
                                         sign(-current_acceleration_rotate.z)*sqrtf(current_acceleration_rotate.x*current_acceleration_rotate.x+current_acceleration_rotate.z*current_acceleration_rotate.z));
                }
                else
                {
                    angle_acc_y = atan2f(current_acceleration_rotate.y,
                                         sqrtf(current_acceleration_rotate.x*current_acceleration_rotate.x+current_acceleration_rotate.z*current_acceleration_rotate.z));
                }
                
                //NSLog(@"AccX %2.2f   AccY %2.2f   AccZ %2.2f",current_acceleration.x,current_acceleration.y,current_acceleration.z);
                
                /***************************************************************************************************************
                 GYRO HANDLE IF AVAILABLE
                 **************************************************************************************************************/
                if (motionManager.deviceMotionAvailable == 1)
                {
                    current_angular_rate_x = motionManager.deviceMotion.rotationRate.x;
                    current_angular_rate_y = motionManager.deviceMotion.rotationRate.y;
                    current_angular_rate_z = motionManager.deviceMotion.rotationRate.z;
                    
                    angle_gyro_x += -current_angular_rate_x * dt;
                    angle_gyro_y += current_angular_rate_y * dt;
                    angle_gyro_z += current_angular_rate_z * dt;
                    
                    if(first_time_gyro == TRUE)
                    {
                        first_time_gyro = FALSE;
                        
                        //Init for the integration samples
                        angle_gyro_x = 0;
                        angle_gyro_y = 0;
                        angle_gyro_z = 0;
                        
                        //Init for the HPF calculus
                        hpf_gyro_x = angle_gyro_x;
                        hpf_gyro_y = angle_gyro_y;
                        hpf_gyro_z = angle_gyro_z;
                        
                        last_angle_gyro_x = 0;
                        last_angle_gyro_y = 0;
                        last_angle_gyro_z = 0;
                    }
                    
                    //HPF on the gyro to keep the hight frequency of the sensor
                    hpf_gyro_x = 0.9 * hpf_gyro_x + 0.9 * (angle_gyro_x - last_angle_gyro_x);
                    hpf_gyro_y = 0.9 * hpf_gyro_y + 0.9 * (angle_gyro_y - last_angle_gyro_y);
                    hpf_gyro_z = 0.9 * hpf_gyro_z + 0.9 * (angle_gyro_z - last_angle_gyro_z);
                    
                    last_angle_gyro_x = angle_gyro_x;
                    last_angle_gyro_y = angle_gyro_y;
                    last_angle_gyro_z = angle_gyro_z;
                }
                
                /******************************************************************************RESULTS AND COMMANDS COMPUTATION
                 *****************************************************************************/
                //Sum of hight gyro frequencies and low accelero frequencies
                float fusion_x = hpf_gyro_y + angle_acc_x;
                float fusion_y = hpf_gyro_x + angle_acc_y;
                
                //NSLog(@"%*.2f  %*.2f  %*.2f  %*.2f  %*.2f",2,-angle_acc_x*180/PI,2,-angle_acc_y*180/PI,2,current_acceleration_rotate.x,2,current_acceleration_rotate.y,2,current_acceleration_rotate.z);
                //Adapt the command values Normalize between -1 = 1.57rad and 1 = 1.57 rad
                //and reverse the values in regards of the screen orientation
                if(motionManager.gyroAvailable == 0 && motionManager.accelerometerAvailable == 1)
                {
                    //Only accelerometer (iphone 3GS)
                    if(1)//screenOrientationRight
                    {
                        theta = -angle_acc_x;
                        phi = -angle_acc_y;
                    }
                    else
                    {
                        theta = angle_acc_x;
                        phi = angle_acc_y;
                    }
                }
                else if (motionManager.deviceMotionAvailable == 1)
                {
                    theta = -fusion_x;
                    phi = fusion_y;
                }
                
                //Clamp the command sent
                theta = theta / M_PI_2;
                phi   = phi / M_PI_2;
                if(theta > 1)
                    theta = 1;
                if(theta < -1)
                    theta = -1;
                if(phi > 1)
                    phi = 1;
                if(phi < -1)
                    phi = -1;
                
                //NSLog(@"ctrldata.iphone_theta %f", theta);
                //NSLog(@"ctrldata.iphone_phi   %f", phi);
                
                if (_settings.isBeginnerMode) {
                    [_aileronChannel setValue:phi * kBeginnerAileronChannelRatio];
                    [_elevatorChannel setValue:theta * kBeginnerElevatorChannelRatio];
                }
                else{
                    [_aileronChannel setValue:phi];
                    [_elevatorChannel setValue:theta];
                }
            }
        }
        else{
            if (accModeReady) {
            }
        }
    }
}

- (void)updateJoysticksForAccModeChanged{
    if (accModeEnabled) {
        if (isLeftHanded) {
            joystickLeftBackgroundImageView.hidden = NO;
            joystickRightBackgroundImageView.hidden = YES;
        }
        else{
            joystickLeftBackgroundImageView.hidden = YES;
            joystickRightBackgroundImageView.hidden = NO;
        }
    }
    else{
        joystickLeftBackgroundImageView.hidden = NO;
        joystickRightBackgroundImageView.hidden = NO;
    }
}


@end
