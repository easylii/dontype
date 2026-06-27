#import "CrashGuard.h"

NSException * _Nullable cg_try(void (^ _Nonnull block)(void)) {
    @try {
        block();
        return nil;
    }
    @catch (NSException *exception) {
        return exception;
    }
}
