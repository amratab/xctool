//
// Copyright 2004-present Facebook. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <Foundation/Foundation.h>

#import "SimulatorInfo.h"

#import "DTiPhoneSimulatorRemoteClient.h"
#import "SimDevice.h"
#import "SimDeviceSet.h"
#import "SimDeviceType.h"
#import "SimRuntime.h"
#import "XcodeBuildSettings.h"
#import "XCToolUtil.h"


static const NSInteger KProductTypeIphone = 1;
static const NSInteger KProductTypeIpad = 2;

@interface SimulatorInfo ()
@property (nonatomic, assign) cpu_type_t cpuType;
@property (nonatomic, copy) NSString *deviceName;
@property (nonatomic, copy) NSString *OSVersion;
@property (nonatomic, copy) NSUUID *deviceUDID;

@property (nonatomic, strong) SimDevice *simulatedDevice;
@property (nonatomic, strong) SimRuntime *simulatedRuntime;

@property (nonatomic, copy) NSString *testHostPath;
@property (nonatomic, copy) NSString *productBundlePath;
@property (nonatomic, assign) cpu_type_t testHostPathCpuType;
@property (nonatomic, assign) cpu_type_t productBundlePathCpuType;
@property (nonatomic, assign) cpu_type_t simulatedCpuType;
@end

@implementation SimulatorInfo

+ (void)prepare
{
  NSAssert([NSThread isMainThread], @"Should be called on main thread");
  [self _warmUpDTiPhoneSimulatorSystemRootCaches];
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    _cpuType = CPU_TYPE_ANY;
    _testHostPathCpuType = 0;
    _productBundlePathCpuType = 0;
    _simulatedCpuType = 0;
  }
  return self;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
  SimulatorInfo *copy = [[SimulatorInfo allocWithZone:zone] init];
  if (copy) {
    copy.buildSettings = _buildSettings;
    copy.cpuType = _cpuType;
    copy.deviceName = _deviceName;
    copy.OSVersion = _OSVersion;
    copy.deviceUDID = _deviceUDID;
  }
  return copy;
}

#pragma mark - Internal Methods

- (void)setBuildSettings:(NSDictionary *)buildSettings
{
  if (_buildSettings == buildSettings || [_buildSettings isEqual:buildSettings]) {
    return;
  }

  _buildSettings = [buildSettings copy];
  _testHostPath = nil;
  _productBundlePath = nil;
  _testHostPathCpuType = 0;
  _productBundlePathCpuType = 0;
  _simulatedCpuType = 0;
}

- (NSString *)testHostPath
{
  if (!_testHostPath) {
    _testHostPath = TestHostPathForBuildSettings(_buildSettings);
  }
  return _testHostPath;
}

- (NSString *)productBundlePath
{
  if (!_productBundlePath) {
    _productBundlePath = ProductBundlePathForBuildSettings(_buildSettings);
  }
  return _productBundlePath;
}

- (cpu_type_t)testHostPathCpuType
{
  if (_testHostPathCpuType == 0) {
    _testHostPathCpuType = CpuTypeForTestBundleAtPath([self testHostPath]);
  }
  return _testHostPathCpuType;
}

- (cpu_type_t)productBundlePathCpuType
{
  if (_productBundlePathCpuType == 0) {
    _productBundlePathCpuType = CpuTypeForTestBundleAtPath([self productBundlePath]);
  }
  return _productBundlePathCpuType;
}

#pragma mark -
#pragma mark Public methods

- (cpu_type_t)simulatedCpuType
{
  if (_cpuType != CPU_TYPE_ANY) {
    return _cpuType;
  }

  if (_simulatedCpuType == 0) {
    /*
     * We use architecture of test host rather than product bundle one
     * if they don't match and test host doesn't support all architectures.
     */
    if ([self testHostPathCpuType] == CPU_TYPE_ANY) {
      _simulatedCpuType = [self productBundlePathCpuType];
    } else {
      _simulatedCpuType = [self testHostPathCpuType];
    }
  }

  return _simulatedCpuType;
}

- (NSNumber *)simulatedDeviceFamily
{
  return @([_buildSettings[Xcode_TARGETED_DEVICE_FAMILY] integerValue]);
}

- (NSString *)simulatedDeviceInfoName
{
  if (_deviceName) {
    return _deviceName;
  }

  if ([_buildSettings[Xcode_SDK_NAME] hasPrefix:@"macosx"]) {
    return @"My Mac";
  }

  switch ([[self simulatedDeviceFamily] integerValue]) {
    case KProductTypeIphone:
      if ([self simulatedCpuType] == CPU_TYPE_I386) {
        _deviceName = @"iPhone 4s";
      } else {
        // CPU_TYPE_X86_64 or CPU_TYPE_ANY
        _deviceName = @"iPhone 5s";
      }
      break;

    case KProductTypeIpad:
      if ([self simulatedCpuType] == CPU_TYPE_I386) {
        _deviceName = @"iPad 2";
      } else {
        // CPU_TYPE_X86_64 or CPU_TYPE_ANY
        _deviceName = @"iPad Air";
      }
      break;
  }
  _deviceName = @"iPhone 6";
  return @"iPhone 6";
}

- (NSString *)simulatedArchitecture
{
  switch ([self simulatedCpuType]) {
    case CPU_TYPE_I386:
      return @"i386";

    case CPU_TYPE_X86_64:
      return @"x86_64";
  }
  return @"i386";
}

- (NSString *)maxSdkVersionForSimulatedDevice
{
  NSMutableArray *runtimes = [SimulatorInfo _runtimesSupportedByDevice:[self simulatedDeviceInfoName]];
  [runtimes sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"version" ascending:YES]]];
  return [[runtimes lastObject] versionString];
}

- (NSString *)simulatedSdkVersion
{
  if (_OSVersion && ![_OSVersion isEqualToString:@"latest"]) {
    return _OSVersion;
  }
  return [self maxSdkVersionForSimulatedDevice];
}

- (NSString *)simulatedSdkRootPath
{
  return @"/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk";
}

- (NSString *)simulatedSdkShortVersion
{
  return @"10.0";
}

- (NSString *)simulatedSdkName
{
  if ([_buildSettings[Xcode_SDK_NAME] hasPrefix:@"macosx"]) {
    return _buildSettings[Xcode_SDK_NAME];
  }

  return @"iphonesimulator10.0";
}

- (SimRuntime *)simulatedRuntime
{
  NSArray *runTimeArray = [SimRuntime supportedRuntimes];
  for (SimRuntime* runTime in runTimeArray) {
    if ([[runTime name]  isEqual: @"iOS 10.0"]) {
      _simulatedRuntime = runTime;
      return _simulatedRuntime;
    }
  }
  return nil;
}

- (SimDevice *)simulatedDevice
{
  if (!_simulatedDevice) {
    SimRuntime *runtime = [self simulatedRuntime];
    if (_deviceUDID) {
      return [SimulatorInfo deviceWithUDID:_deviceUDID];
    } else {
      SimDeviceType *deviceType = [SimDeviceType supportedDeviceTypesByAlias][[self simulatedDeviceInfoName]];
      NSAssert(deviceType != nil, @"Unable to find SimDeviceType for the device with name \"%@\". Available device names: %@", [self simulatedDeviceInfoName], [[SimDeviceType supportedDeviceTypesByAlias] allKeys]);
      for (SimDevice *device in [[SimDeviceSet defaultSet] availableDevices]) {
        if ([device.deviceType isEqual:deviceType] &&
            [device.runtime isEqual:runtime]) {
          _simulatedDevice = device;
          break;
        }
      }
    }

    NSAssert(_simulatedDevice != nil, @"Simulator with name \"%@\" doesn't have configuration with sdk version \"%@\". Available configurations: %@.", [self simulatedDeviceInfoName], runtime.versionString, [SimulatorInfo _availableDeviceConfigurationsInHumanReadableFormat]);
  }
  return _simulatedDevice;
}

- (NSNumber *)launchTimeout
{
  NSString *launchTimeoutString = _buildSettings[Xcode_LAUNCH_TIMEOUT];
  if (launchTimeoutString) {
    return @(launchTimeoutString.intValue);
  }
  return @30;
}

/*
 * Passing the same simulator environment as Xcode 6.4.
 */
- (NSMutableDictionary *)simulatorLaunchEnvironment
{
  NSString *sdkName = _buildSettings[Xcode_SDK_NAME];
  NSString *ideBundleInjectionLibPath = [_buildSettings[Xcode_PLATFORM_DIR] stringByAppendingPathComponent:@"Developer/Library/PrivateFrameworks/IDEBundleInjection.framework/IDEBundleInjection"];
  NSMutableDictionary *environment = nil;
  NSMutableArray *librariesToInsert = [NSMutableArray array];
  if ([sdkName hasPrefix:@"macosx"]) {
    environment = OSXTestEnvironment(_buildSettings);
    [librariesToInsert addObject:[XCToolLibPath() stringByAppendingPathComponent:@"otest-shim-osx.dylib"]];
  } else if ([sdkName hasPrefix:@"iphonesimulator"]) {
    environment = IOSTestEnvironment(_buildSettings);
    [librariesToInsert addObject:[XCToolLibPath() stringByAppendingPathComponent:@"otest-shim-ios.dylib"]];
  } else if ([sdkName hasPrefix:@"appletvsimulator"]) {
    environment = TVOSTestEnvironment(_buildSettings);
    [librariesToInsert addObject:[XCToolLibPath() stringByAppendingPathComponent:@"otest-shim-ios.dylib"]];
  } else {
    NSAssert(false, @"'%@' sdk is not yet supported", sdkName);
  }
  [librariesToInsert addObject:ideBundleInjectionLibPath];

  [environment addEntriesFromDictionary:@{
    @"DYLD_INSERT_LIBRARIES" : [librariesToInsert componentsJoinedByString:@":"],
    @"NSUnbufferedIO" : @"YES",
    @"XCInjectBundle" : [self productBundlePath],
    @"XCInjectBundleInto" : [self testHostPath],
    @"AppTargetLocation": [self testHostPath],
    @"TestBundleLocation": [self productBundlePath],
  }];

  return environment;
}

#pragma mark -
#pragma mark Class Methods

+ (NSArray *)availableDevices
{
  return [[SimDeviceType supportedDeviceTypes] valueForKeyPath:@"name"];
}

+ (BOOL)isDeviceAvailableWithAlias:(NSString *)deviceName
{
  return [SimDeviceType supportedDeviceTypesByAlias][deviceName] != nil;
}

+ (SimDevice *)deviceWithUDID:(NSUUID *)deviceUDID
{
  for (SimDevice *device in [[SimDeviceSet defaultSet] availableDevices]) {
    if ([device.UDID isEqual:deviceUDID]) {
      return device;
    }
  }
  return nil;
}

+ (NSString *)deviceNameForAlias:(NSString *)deviceAlias
{
  SimDeviceType *deviceType = [SimDeviceType supportedDeviceTypesByAlias][deviceAlias];
  return [deviceType name];
}

+ (BOOL)isSdkVersion:(NSString *)sdkVersion supportedByDevice:(NSString *)deviceName
{
  NSAssert(sdkVersion != nil, @"Sdk version shouldn't be nil.");
  NSMutableArray *runtimes = [self _runtimesSupportedByDevice:deviceName];
  if ([runtimes count] == 0) {
    return NO;
  }

  if ([sdkVersion isEqualToString:@"latest"]) {
    return YES;
  }

  for (SimRuntime *runtime in runtimes) {
    if ([runtime.versionString hasPrefix:sdkVersion]) {
      return YES;
    }
  }

  return NO;
}

+ (NSArray *)availableSdkVersions
{
  return [[SimRuntime supportedRuntimes] valueForKeyPath:@"versionString"];
}

+ (NSArray *)sdksSupportedByDevice:(NSString *)deviceName
{
  NSArray *runtimes = [self _runtimesSupportedByDevice:deviceName];
  return [runtimes valueForKeyPath:@"versionString"];
}

+ (cpu_type_t)cpuTypeForDevice:(NSString *)deviceName
{
  SimDeviceType *deviceType = [SimDeviceType supportedDeviceTypesByAlias][deviceName];
  if ([deviceType.supportedArchs containsObject:@(CPU_TYPE_X86_64)]) {
    return CPU_TYPE_X86_64;
  } else {
    return CPU_TYPE_I386;
  }
}

#pragma mark -
#pragma mark Helpers

+ (NSMutableArray *)_runtimesSupportedByDevice:(NSString *)deviceName
{
  NSMutableArray *supportedRuntimes = [NSMutableArray array];
  SimDeviceType *deviceType = [SimDeviceType supportedDeviceTypesByAlias][deviceName];
  NSAssert(deviceType != nil, @"Unable to find SimDeviceType for the device with name \"%@\". Available device names: %@", deviceName, [[SimDeviceType supportedDeviceTypesByAlias] allKeys]);
  for (SimRuntime *runtime in [SimRuntime supportedRuntimes]) {
    if ([runtime supportsDeviceType:deviceType]) {
      [supportedRuntimes addObject:runtime];
    }
  }
  return supportedRuntimes;
}

+ (SimRuntime *)_runtimeForSDKPath:(NSString *)sdkPath
{
  NSArray *runTimeArray = [SimRuntime supportedRuntimes];
  for (SimRuntime* runTime in runTimeArray) {
      if ([[runTime name]  isEqual: @"iOS 10.0"]) {
        return runTime;
      }
  }
  return nil;
}

+ (NSArray *)_availableDeviceConfigurationsInHumanReadableFormat
{
  NSMutableArray *configs = [NSMutableArray array];
  for (SimDevice *device in [[SimDeviceSet defaultSet] availableDevices]) {
    [configs addObject:[NSString stringWithFormat:@"%@: %@", device.name, device.runtime.name]];
  }
  return configs;
}

#pragma mark -
#pragma mark Caching methods

/*
 * Caches `DTiPhoneSimulatorSystemRoot` instances.
 *
 * `sdkRootPath` -> `DTiPhoneSimulatorSystemRoot *`
 * `platformName` -> `NSDictionary *`: `sdkVersion` -> `DTiPhoneSimulatorSystemRoot *`
 *
 */
static NSDictionary *__systemRootsSdkPlatformVersionMap;
static NSDictionary *__systemRootsSdkPathMap;

+ (void)_warmUpDTiPhoneSimulatorSystemRootCaches
{
}

@end


