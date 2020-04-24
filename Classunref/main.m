//
//  main.m
//  Classunref
//
//  Created by zengchao on 2020/4/22.
//  Copyright © 2020 zengchao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MachOParse.h"
#import <mach-o/stab.h>

int main(int argc, const char * argv[]) {
    
    @autoreleasepool {
        
        if (argc < 2) {
            
            printf("Usage: Classunref miss executable path \n");
            return -1;
        }
        
        MachOParse *parse = [[MachOParse alloc] initWithFilePath: [NSString stringWithUTF8String:argv[1]]];
        [parse startParse];
    }
    
    return 0;
}
