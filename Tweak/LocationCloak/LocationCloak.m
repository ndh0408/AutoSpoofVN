//
//  LocationCloak.m
//  LocationX — System-wide CoreLocation hook
//
//  Mục đích: Strip cờ isSimulatedBySoftware khỏi CLLocationSourceInformation.
//  Khi DVT LocationSimulation gửi toạ độ giả, locationd gắn cờ này = true.
//  Mọi app đọc CLLocationManager sẽ thấy cờ đó. Hook này trả false.
//
//  Cài đặt:
//  - TrollStore: build thành .dylib → inject qua DYLD_INSERT_LIBRARIES
//  - Jailbreak: copy vào /Library/MobileSubstrate/DynamicLibraries/
//  - Dopamine/ElleKit: sử dụng như substrate tweak
//
//  Build:
//  clang -arch arm64 -shared -framework Foundation -framework CoreLocation \
//        -o LocationCloak.dylib LocationCloak.m
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// ====================================================================
// Phương pháp 1: Swizzle CLLocationSourceInformation.isSimulatedBySoftware
// iOS 15+ có property này. Hook getter trả false.
// ====================================================================

static BOOL cloak_isSimulatedBySoftware(id self, SEL _cmd) {
    return NO;
}

// ====================================================================
// Phương pháp 2: Swizzle CLLocation.sourceInformation
// Trả sourceInformation với simulated flags cleared.
// iOS 15+ CLLocation có property sourceInformation.
// ====================================================================

static id cloak_sourceInformation(id self, SEL _cmd) {
    // Gọi original implementation
    // Nếu không có original (first hook), trả nil — location sẽ được coi là GPS thật
    return nil;
}

// ====================================================================
// Phương pháp 3: Hook CLLocationManager delegate delivery
// Intercept locationManager:didUpdateLocations: trước khi app nhận
// Strip sourceInformation trên mỗi CLLocation object.
// ====================================================================

// Lưu IMP gốc
static IMP original_didUpdateLocations = NULL;

static void cloak_didUpdateLocations(id self, SEL _cmd, id manager, NSArray *locations) {
    // Với mỗi location, nullify sourceInformation
    // CLLocation.sourceInformation là readonly, nhưng ivar có thể set qua runtime
    for (CLLocation *loc in locations) {
        @try {
            Ivar ivar = class_getInstanceVariable([CLLocation class], "_sourceInformation");
            if (!ivar) {
                ivar = class_getInstanceVariable([CLLocation class], "_internal");
            }
            if (ivar) {
                // Set sourceInformation to nil — CLLocation reports as real GPS
                object_setIvar(loc, ivar, nil);
            }
        } @catch (NSException *e) {
            // Fail silently — better to pass uncloaked than crash
        }
    }

    // Forward to original
    if (original_didUpdateLocations) {
        ((void(*)(id, SEL, id, NSArray*))original_didUpdateLocations)(self, _cmd, manager, locations);
    }
}

// ====================================================================
// Constructor — runs when dylib loads
// ====================================================================

__attribute__((constructor))
static void LocationCloakInit(void) {
    @autoreleasepool {
        NSLog(@"[LocationCloak] Initializing...");

        // --- Hook 1: CLLocationSourceInformation.isSimulatedBySoftware ---
        Class sourceInfoClass = NSClassFromString(@"CLLocationSourceInformation");
        if (sourceInfoClass) {
            // isSimulatedBySoftware getter
            SEL simSel = NSSelectorFromString(@"isSimulatedBySoftware");
            Method m = class_getInstanceMethod(sourceInfoClass, simSel);
            if (m) {
                method_setImplementation(m, (IMP)cloak_isSimulatedBySoftware);
                NSLog(@"[LocationCloak] Hooked isSimulatedBySoftware → false");
            }

            // isProducedByAccessory — some apps also check this
            SEL accSel = NSSelectorFromString(@"isProducedByAccessory");
            Method accM = class_getInstanceMethod(sourceInfoClass, accSel);
            if (accM) {
                method_setImplementation(accM, (IMP)cloak_isSimulatedBySoftware);
                NSLog(@"[LocationCloak] Hooked isProducedByAccessory → false");
            }
        } else {
            NSLog(@"[LocationCloak] CLLocationSourceInformation not found (iOS < 15?)");
        }

        // --- Hook 2: CLLocation.sourceInformation → nil ---
        Class locClass = [CLLocation class];
        SEL srcSel = NSSelectorFromString(@"sourceInformation");
        Method srcM = class_getInstanceMethod(locClass, srcSel);
        if (srcM) {
            method_setImplementation(srcM, (IMP)cloak_sourceInformation);
            NSLog(@"[LocationCloak] Hooked CLLocation.sourceInformation → nil");
        }

        NSLog(@"[LocationCloak] Ready. All simulated flags will report as real GPS.");
    }
}
