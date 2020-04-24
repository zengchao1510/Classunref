//
//  MachOParse.h
//  Classunref
//
//  Created by zengchao on 2020/4/22.
//  Copyright © 2020 zengchao. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MachOParse : NSObject

- (instancetype)initWithFilePath:(NSString *)path;

- (void)startParse;

@end

NS_ASSUME_NONNULL_END
