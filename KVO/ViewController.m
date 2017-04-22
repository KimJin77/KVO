//
//  ViewController.m
//  KVO
//
//  Created by Kim on 2017/4/21.
//  Copyright © 2017年 UFun Network. All rights reserved.
//

#import "ViewController.h"
#import "Person.h"
#import "NSObject+KJKeyValueObserving.h"

@interface ViewController ()
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    Person *person = [[Person alloc] init];
    [person kj_addObserver:self forKey:@"name" block:^(id  _Nonnull observer, NSString * _Nullable key, id  _Nullable newValue, id  _Nullable oldValue) {
        NSLog(@"Change: %@", newValue);
    }];
    person.name = @"Jin";
    [person kj_removeObserver:self forKey:@"name"];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
