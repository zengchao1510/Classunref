//
//  MachOLayout.m
//  Classunref
//
//  Created by zengchao on 2020/4/22.
//  Copyright © 2020 zengchao. All rights reserved.
//

#import "MachOLayout.h"
#import "loader.h"
#import <mach-o/swap.h>

#define MATCH_STRUCT(obj,location) \
struct obj const * obj = (struct obj *)[self imageAt:(location)]; \
if (!obj) [NSException raise:@"null exception" format:@#obj " is null"];

#define NSSTRING(C_STR) [NSString stringWithCString: (char *)(C_STR) encoding: [NSString defaultCStringEncoding]]

@interface MachOLayout ()

@property (nonatomic, strong) NSData *fileData;

@end

@implementation MachOLayout

- (instancetype)initWithFileData:(NSData *)fileData {
    
    self = [super init];
    if (self) {
        
        self.fileData = fileData;
        symbolNames = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)doMainTasks {
    
    uint32_t      ncmds;
    uint32_t      sizeofcmds;
    
    sections_64.push_back(NULL);
    
    NSString * lastNodeCaption;
    
    // 64bit
    MATCH_STRUCT(mach_header_64,imageOffset)
    ncmds = mach_header_64->ncmds;
    sizeofcmds = mach_header_64->sizeofcmds;
    
    {
        uint32_t fileOffset = imageOffset + sizeof(struct mach_header_64);
        for (uint32_t ncmd = 0; ncmd < ncmds; ++ncmd) {
            
            MATCH_STRUCT(load_command, fileOffset)
            
            commands.push_back(load_command);
            
            @try {
            
                [self getSectionHeaderAtLocation:fileOffset length:load_command->cmdsize command:load_command->cmd];

            } @catch(NSException * exception) {

                [self printException:exception caption:lastNodeCaption];
            }
            
            fileOffset += load_command->cmdsize;
        }
    }
    
    [self getSymbols64];
}

- (void)getSectionHeaderAtLocation:(uint32_t)location
                           length:(uint32_t)length
                          command:(uint32_t)command {

    switch (command) {
            
        case LC_SEGMENT_64: {
            
            MATCH_STRUCT(segment_command_64,location)
            
            segments_64.push_back(segment_command_64);
            
            for (uint32_t nsect = 0; nsect < segment_command_64->nsects; ++nsect) {
                
                uint32_t sectionloc = location + sizeof(struct segment_command_64) + nsect * sizeof(struct section_64);
                MATCH_STRUCT(section_64, sectionloc)
                
                sections_64.push_back(section_64);
            }
            
        } break;
            
        case LC_SYMTAB: {
            
            MATCH_STRUCT(symtab_command,location)
            
            strtab = (char *)((uint8_t *)[self.fileData bytes] + imageOffset + symtab_command->stroff);
            
            _symtab_command = symtab_command;
            
            for (uint32_t nsym = 0; nsym < symtab_command->nsyms; ++nsym) {
                
                if ([self is64bit]) {
                    
                    // 64bit
                    MATCH_STRUCT(nlist_64, imageOffset + symtab_command->symoff + nsym * sizeof(struct nlist_64))
                    symbols_64.push_back (nlist_64);
                }
            }
            
        } break;
            
        default: break;
    }
}

- (struct section_64 const *)findSectionByName:(char const *)sectname
                                    andSegment:(char const *)segname {
    
    for (Section64Vector::const_iterator sectIter = ++sections_64.begin();
         sectIter != sections_64.end(); ++sectIter) {
        
        struct section_64 const *section_64 = *sectIter;
        if ((segname == NULL || strncmp(section_64->segname,segname,16) == 0) &&
            strncmp(section_64->sectname,sectname,16) == 0) {
            
            return section_64;
        }
    }
    return NULL;
}

- (void)getSymbols64 {
    
    uint32_t location = _symtab_command->symoff + imageOffset;
    uint32_t count = _symtab_command->nsyms;
    for (uint32_t nsym = 0; nsym < count; ++nsym) {
        
        MATCH_STRUCT(nlist_64, location + nsym * sizeof(struct nlist_64))
        
        NSString *symbolName = NSSTRING(strtab + nlist_64->n_un.n_strx);
        
        if ((nlist_64->n_type & N_TYPE) == N_SECT) {
            
            if ((nlist_64->n_type & N_STAB) == 0) {
                
                NSString *nameToStore = [symbolNames objectForKey:[NSNumber numberWithUnsignedLongLong:nlist_64->n_value]];
                nameToStore = (nameToStore != nil
                               ? [nameToStore stringByAppendingFormat:@"(%@)", symbolName]
                               : [NSString stringWithFormat:@"0x%qX (%@)", nlist_64->n_value, symbolName]);
                
                [symbolNames setObject:nameToStore
                                forKey:[NSNumber numberWithUnsignedLongLong:nlist_64->n_value]];
                
                NSLog(@"--------%@---------",NSSTRING(strtab + nlist_64->n_desc));
            }
            
        } else {

            uint64_t key = *symbols_64.begin() - nlist_64 - 1;
            [symbolNames setObject:symbolName
                            forKey:[NSNumber numberWithUnsignedLongLong:key]];
        }
    }
}

- (NSArray *)getClassList {

    struct section_64 const *classlist = [self findSectionByName:"__class_list" andSegment:"__OBJC2"];
    if (classlist == NULL) {
        
        classlist = [self findSectionByName:"__objc_classlist" andSegment:"__DATA"];
    }
    
    uint32_t location = classlist->offset + imageOffset;
    uint32_t length = classlist->size;
    
    NSRange range = NSMakeRange(location,0);
    NSString *lastReadHex;
    
    NSMutableArray *classList = [NSMutableArray array];
    while (NSMaxRange(range) < location + length) {
        
        uint64_t rva64 = [self read_uint64:range lastReadHex:&lastReadHex];
        NSString *symbolName = [self findSymbolAtRVA64: rva64];
        [classList addObject:symbolName];
        
//        NSLog(@"class ======= %@", symbolName);
    }
    
    return [classList copy];
}

- (NSArray *)getClassRefsList {
    
    struct section_64 const *classrefListSec = [self findSectionByName:"__class_list" andSegment:"__OBJC2"];
    if (classrefListSec == NULL) {
        
        classrefListSec = [self findSectionByName:"__objc_classrefs" andSegment:"__DATA"];
    }
    
    uint32_t location = classrefListSec->offset + imageOffset;
    uint32_t length = classrefListSec->size;
    
    NSRange range = NSMakeRange(location,0);
    NSString *lastReadHex;
    
    NSMutableArray *classrefList = [NSMutableArray array];
    while (NSMaxRange(range) < location + length) {
        
        uint64_t rva64 = [self read_uint64:range lastReadHex:&lastReadHex];
        NSString *symbolName = [self findSymbolAtRVA64: rva64];
        [classrefList addObject:symbolName];
        
//        NSLog(@"classref ======= %@", symbolName);
    }
    
    return [classrefList copy];
}

- (NSArray *)getSuperRefsList {
    
    struct section_64 const *supperrefListSec = [self findSectionByName:"__super_refs" andSegment:"__OBJC2"];
    if (supperrefListSec == NULL)
        
        supperrefListSec = [self findSectionByName:"__objc_superrefs" andSegment:"__DATA"];
    
    uint32_t location = supperrefListSec->offset + imageOffset;
    uint32_t length = supperrefListSec->size;
    
    NSRange range = NSMakeRange(location,0);
    NSString *lastReadHex;
    
    NSMutableArray *superrefsList = [NSMutableArray array];
    while (NSMaxRange(range) < location + length) {
        
        uint64_t rva64 = [self read_uint64:range lastReadHex:&lastReadHex];
        NSString *symbolName = [self findSymbolAtRVA64: rva64];
        [superrefsList addObject:symbolName];
        
//        NSLog(@"superref ======= %@", symbolName);
    }
    
    return [superrefsList copy];
}

- (uint64_t)read_uint64:(NSRange &)range lastReadHex:(NSString **)lastReadHex {
    
    uint64_t buffer;
    range = NSMakeRange(NSMaxRange(range),sizeof(uint64_t));
    [self.fileData getBytes:&buffer range:range];
    if (lastReadHex) *lastReadHex = [NSString stringWithFormat:@"%.16qX",buffer];
    return buffer;
}

- (NSString *)findSymbolAtRVA64:(uint64_t)rva64 {
    
    NSParameterAssert([self is64bit] == YES);
    if ((int32_t)rva64 < 0) {
        
        rva64 |= 0xffffffff00000000LL;
    }
    
    NSString *symbolName = [symbolNames objectForKey:[NSNumber numberWithUnsignedLongLong:rva64]];
    return (symbolName != nil ? symbolName : [NSString stringWithFormat:@"0x%qX",rva64]);
}

- (BOOL)is64bit {
    
    MATCH_STRUCT(mach_header,imageOffset);
    return ((mach_header->cputype & CPU_ARCH_ABI64) == CPU_ARCH_ABI64);
}

- (void const *)imageAt:(uint32_t)location {
    
    auto p = (uint8_t const *)[self.fileData bytes];
    return p ? p + location : NULL;
}

- (void)printException:(NSException *)exception caption:(NSString *)caption {
    
    @synchronized(self) {
        
        NSLog(@"%@: Exception (%@): %@", self, caption, [exception name]);
        NSLog(@"  Reason: %@", [exception reason]);
        NSLog(@"  User Info: %@", [exception userInfo]);
        NSLog(@"  Backtrace:\n%@", [exception callStackSymbols]);
    }
}

- (NSString *)getNameForCommand:(uint32_t)cmd {
    
    switch(cmd) {
            
        default:                      return @"???";
        case LC_SEGMENT:              return @"LC_SEGMENT";
        case LC_SYMTAB:               return @"LC_SYMTAB";
        case LC_SYMSEG:               return @"LC_SYMSEG";
        case LC_THREAD:               return @"LC_THREAD";
        case LC_UNIXTHREAD:           return @"LC_UNIXTHREAD";
        case LC_LOADFVMLIB:           return @"LC_LOADFVMLIB";
        case LC_IDFVMLIB:             return @"LC_IDFVMLIB";
        case LC_IDENT:                return @"LC_IDENT";
        case LC_FVMFILE:              return @"LC_FVMFILE";
        case LC_PREPAGE:              return @"LC_PREPAGE";
        case LC_DYSYMTAB:             return @"LC_DYSYMTAB";
        case LC_LOAD_DYLIB:           return @"LC_LOAD_DYLIB";
        case LC_ID_DYLIB:             return @"LC_ID_DYLIB";
        case LC_LOAD_DYLINKER:        return @"LC_LOAD_DYLINKER";
        case LC_ID_DYLINKER:          return @"LC_ID_DYLINKER";
        case LC_PREBOUND_DYLIB:       return @"LC_PREBOUND_DYLIB";
        case LC_ROUTINES:             return @"LC_ROUTINES";
        case LC_SUB_FRAMEWORK:        return @"LC_SUB_FRAMEWORK";
        case LC_SUB_UMBRELLA:         return @"LC_SUB_UMBRELLA";
        case LC_SUB_CLIENT:           return @"LC_SUB_CLIENT";
        case LC_SUB_LIBRARY:          return @"LC_SUB_LIBRARY";
        case LC_TWOLEVEL_HINTS:       return @"LC_TWOLEVEL_HINTS";
        case LC_PREBIND_CKSUM:        return @"LC_PREBIND_CKSUM";
        case LC_LOAD_WEAK_DYLIB:      return @"LC_LOAD_WEAK_DYLIB";
        case LC_SEGMENT_64:           return @"LC_SEGMENT_64";
        case LC_ROUTINES_64:          return @"LC_ROUTINES_64";
        case LC_UUID:                 return @"LC_UUID";
        case LC_RPATH:                return @"LC_RPATH";
        case LC_CODE_SIGNATURE:       return @"LC_CODE_SIGNATURE";
        case LC_SEGMENT_SPLIT_INFO:   return @"LC_SEGMENT_SPLIT_INFO";
        case LC_REEXPORT_DYLIB:       return @"LC_REEXPORT_DYLIB";
        case LC_LAZY_LOAD_DYLIB:      return @"LC_LAZY_LOAD_DYLIB";
        case LC_ENCRYPTION_INFO:      return @"LC_ENCRYPTION_INFO";
        case LC_ENCRYPTION_INFO_64:   return @"LC_ENCRYPTION_INFO_64";
        case LC_DYLD_INFO:            return @"LC_DYLD_INFO";
        case LC_DYLD_INFO_ONLY:       return @"LC_DYLD_INFO_ONLY";
        case LC_LOAD_UPWARD_DYLIB:    return @"LC_LOAD_UPWARD_DYLIB";
        case LC_VERSION_MIN_MACOSX:   return @"LC_VERSION_MIN_MACOSX";
        case LC_VERSION_MIN_IPHONEOS: return @"LC_VERSION_MIN_IPHONEOS";
        case LC_FUNCTION_STARTS:      return @"LC_FUNCTION_STARTS";
        case LC_DYLD_ENVIRONMENT:     return @"LC_DYLD_ENVIRONMENT";
        case LC_MAIN:                 return @"LC_MAIN";
        case LC_DATA_IN_CODE:         return @"LC_DATA_IN_CODE";
        case LC_SOURCE_VERSION:       return @"LC_SOURCE_VERSION";
        case LC_DYLIB_CODE_SIGN_DRS:  return @"LC_DYLIB_CODE_SIGN_DRS";
        case LC_LINKER_OPTION:        return @"LC_LINKER_OPTION";
        case LC_LINKER_OPTIMIZATION_HINT: return @"LC_LINKER_OPTIMIZATION_HINT";
    }
}

- (struct section_64 const *)findSection64ByName:(char const *)sectname
                                     andSegment:(char const *)segname {
    
    for (Section64Vector::const_iterator sectIter = ++sections_64.begin();
         sectIter != sections_64.end(); ++sectIter) {
        
        struct section_64 const * section_64 = *sectIter;
        if ((segname == NULL || strncmp(section_64->segname,segname,16) == 0) &&
            strncmp(section_64->sectname,sectname,16) == 0) {
            
            return section_64;
        }
    }
    return NULL;
}

@end
