//
//  NSObject+KJKeyValueObserving.m
//  KVO
//
//  Created by Kim on 2017/4/22.
//  Copyright © 2017年 UFun Network. All rights reserved.
//

#import "NSObject+KJKeyValueObserving.h"
#import <objc/runtime.h>
#import <objc/message.h>

NSString *const KJKVONotifyingPrefix = @"KJKVONotifying_";
NSString *const KJKVOAssociatedObservers = @"KJKVOAssociatedObservers";

// MARK: - KJObservingInfo

NS_ASSUME_NONNULL_BEGIN

@interface KJObservingInfo : NSObject

@property (nullable, nonatomic, weak) id observer;
@property (nullable, nonatomic, copy) NSString *key;
@property (nullable, nonatomic, copy) KJObservingBlock block;

- (instancetype)initWithObserver:(id)observer key:(NSString *)key block:(KJObservingBlock)block;

@end
NS_ASSUME_NONNULL_END

@implementation KJObservingInfo

- (instancetype)initWithObserver:(id)observer key:(NSString *)key block:(KJObservingBlock)block {
    self = [super init];
    if (self) {
        _observer = observer;
        _key = key;
        _block = block;
    }
    return self;
}

@end

@implementation NSObject (KJKeyValueObserving)

- (void)kj_addObserver:(nonnull id)observer forKey:(nonnull NSString *)key block:(nullable KJObservingBlock)block {
    // 获取原始类的setter方法
    SEL setterSelector = NSSelectorFromString([self setterForKey:key]);
    Method setterMethod = class_getInstanceMethod([self class], setterSelector);
    // 如果方法不存在的话，则表明没有该对象，抛出exception
    if (!setterMethod) {
        NSString *reason = [NSString stringWithFormat:@"Object %@ does not have setter %@", self, [self setterForKey:key]];
        NSException *exception = [NSException exceptionWithName:NSInvalidArgumentException reason:reason userInfo:nil];
        @throw exception;
        return;
    }

    // 获取当前类名
    Class clazz = object_getClass(self);
    NSString *clazzName = NSStringFromClass(clazz);

    // 如果不是替代的类的话，创建之
    if (![clazzName hasPrefix:KJKVONotifyingPrefix]) {
        clazz = [self createKVOClassWithOriginalName:clazzName];
        // 将原来的类注册为新的替代的类
        object_setClass(self, clazz);
    }

    // 添加自定义的setter方法
    if (![self hasSelector:setterSelector]) {
        class_addMethod(clazz, setterSelector, (IMP)kvo_setter, method_getTypeEncoding(setterMethod));
    }

    KJObservingInfo *info = [[KJObservingInfo alloc] initWithObserver:observer key:key block:block];
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void *)KJKVOAssociatedObservers);
    if (!observers) {
        observers = [NSMutableArray array];
        objc_setAssociatedObject(self, (__bridge const void *)KJKVOAssociatedObservers, observers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [observers addObject:info];
}

- (void)kj_removeObserver:(nonnull id)observer forKey:(nonnull NSString *)key {
	NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void *)KJKVOAssociatedObservers);
    KJObservingInfo *infoToRemove;
    for (KJObservingInfo *info in observers) {
        if ([info.key isEqualToString:key] && [info.observer isEqual:observer]) {
            infoToRemove = info;
            break;
        }
    }
    [observers removeObject:infoToRemove];
}

- (Class)createKVOClassWithOriginalName:(nonnull NSString *)name {
    NSString *kvoClassName = [KJKVONotifyingPrefix stringByAppendingString:name];
    Class clazz = NSClassFromString(kvoClassName);
    if (clazz) {
        return clazz;
    }

    // 获取原始类， 创建替代类
    Class originalClazz = object_getClass(self);
    Class kvoClazz = objc_allocateClassPair(originalClazz, kvoClassName.UTF8String, 0);

    // 获取`class`方法，隐藏替换
    Method classMethod = class_getInstanceMethod(originalClazz, @selector(class));
    class_addMethod(kvoClazz, @selector(class), (IMP)kvo_class, method_getTypeEncoding(classMethod));
    objc_registerClassPair(kvoClazz);
    return kvoClazz;
}

// MARK: - C Methods

static void kvo_setter(id self, SEL _cmd, id newValue) {
    NSString *setterName = NSStringFromSelector(_cmd);
    NSString *getterName = [self getterForSetter:setterName];

    if (!getterName) {
        NSString *reason = [NSString stringWithFormat:@"Object %@ does not have setter %@", self, setterName];
        NSException *exception = [NSException exceptionWithName:NSInvalidArgumentException reason:reason userInfo:nil];
        @throw exception;
        return;
    }

    id oldValue = [self valueForKey:getterName];

    struct objc_super superClazz = {
        .receiver = self,
        .super_class = class_getSuperclass(object_getClass(self))
    };

    void (*objc_msgSendSuperCasted)(void *, SEL, id) = (void *)objc_msgSendSuper; // 强制转换
    objc_msgSendSuperCasted(&superClazz, _cmd, newValue); // 调用原始类的setter方法

    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void *)KJKVOAssociatedObservers);
    for (KJObservingInfo *info in observers) {
        if ([info.key isEqualToString:getterName]) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                info.block(self, getterName, newValue, oldValue);
            });
        }
    }
}

Class kvo_class(id self, SEL _cmd) {
    Class clazz = object_getClass(self); // KVO
    Class superClazz = class_getSuperclass(clazz); // original
    return superClazz;
}

// MARK: - Util

- (BOOL)hasSelector:(SEL)selector {
    Class clazz = object_getClass(self);
    unsigned int count;
    Method *methodList = class_copyMethodList(clazz, &count);
    for (int i = 0; i < count; i++) {
        if (method_getName(methodList[i]) == selector) {
            free(methodList);
            return YES;
        }
    }
    return NO;
}

- (nullable NSString *)setterForKey:(nullable NSString *)key {
    NSString *nKey = [key stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:[[key substringToIndex:1] uppercaseString]];
    NSString *setter = [NSString stringWithFormat:@"set%@:", nKey];
    return setter;
}

- (nullable NSString *)getterForSetter:(nullable NSString *)setterName {
    if (![setterName hasPrefix:@"set"] || setterName.length == 0) {
        return nil;
    }

    NSString *key = [setterName substringWithRange:NSMakeRange(3, setterName.length - 4)];
    NSString *firstLetter = [[key substringToIndex:1] lowercaseString];
    key = [key stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:firstLetter];
    return key;
}

@end
