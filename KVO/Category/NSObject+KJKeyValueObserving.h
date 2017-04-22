//
//  NSObject+KJKeyValueObserving.h
//  KVO
//
//  Created by Kim on 2017/4/22.
//  Copyright © 2017年 UFun Network. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^KJObservingBlock)(id _Nonnull observer, NSString * _Nullable key, id _Nullable newValue, id _Nullable oldValue);

@interface NSObject (KJKeyValueObserving)

/**
 Add observer for key

 @param observer Observer object
 @param key Key that will be observed
 @param block Handler block
 */
- (void)kj_addObserver:(nonnull id)observer forKey:(nonnull NSString *)key block:(nullable KJObservingBlock)block;

/**
 Remove observer for key

 @param observer Observer object
 @param key Key which is observing
 */
- (void)kj_removeObserver:(nonnull id)observer forKey:(nonnull NSString *)key;

@end
