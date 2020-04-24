//
//  MachOParse.m
//  Classunref
//
//  Created by zengchao on 2020/4/22.
//  Copyright © 2020 zengchao. All rights reserved.
//

#import "MachOParse.h"
#import "fat.h"
#import "loader.h"
#import <mach-o/swap.h>
#import "MachOLayout.h"

@interface MachOParse ()

@property (nonatomic) NSString      *fileName;
@property (nonatomic) NSMutableData *fileData;
@property (nonatomic) NSString      *caption;
@property (nonatomic) NSMutableArray *layouts;
@property (nonatomic) MachOLayout   *layout;
@property (nonatomic) uint32_t      imageOffset;

@end

@implementation MachOParse

- (instancetype)initWithFilePath:(NSString *)path {
    
    self = [super init];
    if (self) {
        
        self.fileName = path;
        
        NSError *error;
        
        NSURL *fileUrl = [NSURL fileURLWithPath:path];
        
        self.fileData = [NSMutableData dataWithContentsOfURL:fileUrl options:NSDataReadingMappedIfSafe error:&error];
        
        NSAssert(!error, @"读取文件内容出错~");
        
        self.layouts = [NSMutableArray array];
    }
    return self;
}

- (void)startParse {
    
    [self createLayoutsLocation:0];
    
    NSArray *classList = [self.layout getClassList];
    NSArray *classrefList = [self.layout getClassRefsList];
    
    NSMutableArray *list = [NSMutableArray array];
    for (int i = 0; i < classList.count; i ++) {

        NSString *className = classList[i];
        BOOL isContains = NO;
        for (int j = 0; j < classrefList.count; j ++) {

            NSString *classrefName = classrefList[j];
            if ([className isEqualToString:classrefName]) {
                
                isContains = YES;
                break;
            }
        }
        if (!isContains) {
            
            [list addObject:className];
        }
    }

    [list enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {

        NSLog(@"%@", obj);
    }];
}

- (void)createLayoutsLocation:(uint32_t)location {
    
    // 读取文件内容前4个字节为魔数
    // 获取文件首地址
    const void *firstAddress = [self.fileData bytes];
    // 获取魔数，uint32_t占用4个字节，uint8_t占用1个字节，所以转换得到的值刚刚好就是魔数的值，location表示地址偏移
    uint32_t magic = *(uint32_t *)((uint8_t *)firstAddress + location);
    
    switch (magic) {
            
        case FAT_MAGIC:
        case FAT_CIGAM: {
            
//            struct fat_header fat_header;
//            [fileData getBytes:&fat_header range:NSMakeRange(location, sizeof(struct fat_header))];
//            if (magic == FAT_CIGAM)
//                swap_fat_header(&fat_header, NX_LittleEndian);
//            [self createFatLayout:parent fat_header:&fat_header];
            
        } break;
            
        case MH_MAGIC_64:
        case MH_CIGAM_64: {
            
            // 获取文件头，判断是大端序还是小端序
            struct mach_header_64 mach_header_64;
            [self.fileData getBytes:&mach_header_64 range:NSMakeRange(location, sizeof(struct mach_header_64))];
            if (magic == MH_CIGAM_64)
                
                swap_mach_header_64(&mach_header_64, NX_LittleEndian);
            
            [self createMachO64LayoutWithMach_header_64:&mach_header_64];
            
        } break;
            
        default: break;
    }
}

- (void)createMachO64LayoutWithMach_header_64:(struct mach_header_64 const *)mach_header_64 {
    
    NSString *machine = [self getMachine:mach_header_64->cputype];
    
    self.caption = [NSString stringWithFormat:@"%@ (%@)",
                    mach_header_64->filetype == MH_OBJECT      ? @"Object " :
                    mach_header_64->filetype == MH_EXECUTE     ? @"Executable " :
                    mach_header_64->filetype == MH_FVMLIB      ? @"Fixed VM Shared Library" :
                    mach_header_64->filetype == MH_CORE        ? @"Core" :
                    mach_header_64->filetype == MH_PRELOAD     ? @"Preloaded Executable" :
                    mach_header_64->filetype == MH_DYLIB       ? @"Shared Library " :
                    mach_header_64->filetype == MH_DYLINKER    ? @"Dynamic Link Editor" :
                    mach_header_64->filetype == MH_BUNDLE      ? @"Bundle" :
                    mach_header_64->filetype == MH_DYLIB_STUB  ? @"Shared Library Stub" :
                    mach_header_64->filetype == MH_DSYM        ? @"Debug Symbols" :
                    mach_header_64->filetype == MH_KEXT_BUNDLE ? @"Kernel Extension" : @"?????",
                    [machine isEqualToString:@"ARM64"] == YES ? [self getARM64Cpu:mach_header_64->cpusubtype] : machine];
    
    self.layout = [[MachOLayout alloc] initWithFileData:self.fileData];
    [self.layout doMainTasks];
}

- (NSString *)getMachine:(cpu_type_t)cputype {
    
    switch (cputype) {
            
        default:                  return @"???";
        case CPU_TYPE_I386:       return @"X86";
        case CPU_TYPE_POWERPC:    return @"PPC";
        case CPU_TYPE_X86_64:     return @"X86_64";
        case CPU_TYPE_POWERPC64:  return @"PPC64";
        case CPU_TYPE_ARM:        return @"ARM";
        case CPU_TYPE_ARM64:      return @"ARM64";
    }
}

- (NSString *)getARM64Cpu:(cpu_subtype_t)cpusubtype {
    
    switch (cpusubtype) {
            
        default:                      return @"???";
        case CPU_SUBTYPE_ARM64_ALL:   return @"ARM64_ALL";
        case CPU_SUBTYPE_ARM64_V8:    return @"ARM64_V8";
    }
}

- (BOOL)isSupportedMachine:(NSString *)machine {
    
    return ([machine isEqualToString:@"X86"] == YES ||
            [machine isEqualToString:@"X86_64"] == YES ||
            [machine isEqualToString:@"ARM"] == YES ||
            [machine isEqualToString:@"ARM64"] == YES);
}


@end
