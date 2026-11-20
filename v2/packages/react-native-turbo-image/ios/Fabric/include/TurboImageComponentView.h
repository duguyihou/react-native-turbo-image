// Kept free of C++ so it is safe to appear in an ObjC umbrella header. The
// C++ surface (codegen props, core types) is confined to the .mm.
//
// This directory is the target's public headers under SwiftPM. A header
// that includes C++ belongs one level up, next to the sources.
#import <React/RCTViewComponentView.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TurboImageComponentView : RCTViewComponentView
@end

NS_ASSUME_NONNULL_END
