#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 执行 block；若它抛出 Objective-C 异常（如 AVAudioEngine installTap 在坏格式下的断言），
/// 捕获并返回该异常，避免整个 App 因 NSException 直接 SIGABRT 崩溃。返回 nil = 正常。
NSException * _Nullable cg_try(void (^ _Nonnull block)(void));

NS_ASSUME_NONNULL_END
