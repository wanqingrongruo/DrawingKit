//
//  ASCGImageBuffer.h
//  DrawingCat
//
//  Created by roni on 2023/2/7.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CGDataProvider.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASCGImageBuffer : NSObject

/// Init a zero-filled buffer with the given length.
- (instancetype)initWithLength:(NSUInteger)length;

@property (readonly) void *mutableBytes NS_RETURNS_INNER_POINTER;

/// Don't do any drawing or call any methods after calling this.
- (CGDataProviderRef)createDataProviderAndInvalidate CF_RETURNS_RETAINED;

@end

NS_ASSUME_NONNULL_END

