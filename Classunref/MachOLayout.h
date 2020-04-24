//
//  MachOLayout.h
//  Classunref
//
//  Created by zengchao on 2020/4/22.
//  Copyright © 2020 zengchao. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <string>
#include <vector>
#include <map>

NS_ASSUME_NONNULL_BEGIN

typedef std::vector<struct load_command const *>          CommandVector;
typedef std::vector<struct segment_command_64 const *>    Segment64Vector;
typedef std::vector<struct section_64 const *>            Section64Vector;

typedef std::vector<struct nlist_64 const *>              NList64Vector;

typedef std::map<uint32_t,std::pair<uint64_t,uint64_t> >        SegmentInfoMap;     // fileOffset --> <address,size>
typedef std::map<uint64_t,std::pair<uint32_t,NSDictionary * __weak> >  SectionInfoMap;  // address    --> <fileOffset,sectionUserInfo>
typedef std::map<uint64_t,uint64_t>                             ExceptionFrameMap;  // LSDA_addr  -->

@interface MachOLayout : NSObject {
    
    uint32_t              imageOffset;  // absolute physical offset of the image in binary
    uint32_t              imageSize;    // size of the image corresponds to this layout
    
    uint64_t              entryPoint;       // instruction pointer in thread command
    
    char const *          strtab;           // pointer to the string table
    
    NList64Vector         symbols_64;
    
    CommandVector         commands;         // load commands
    Segment64Vector       segments_64;      // segment entries for 64-bit architectures
    Section64Vector       sections_64;      // section entries for 64-bit architectures
    
    SegmentInfoMap        segmentInfo;      // segment info lookup table by offset
    SectionInfoMap        sectionInfo;      // section info lookup table by address
    ExceptionFrameMap     lsdaInfo;         // LSDA info lookup table by address
    
    struct symtab_command const *_symtab_command;
    
    NSMutableDictionary   *symbolNames;     // symbol names by address;
}

- (instancetype)initWithFileData:(NSData *)fileData;
- (void)doMainTasks;

- (NSArray *)getClassList;
- (NSArray *)getClassRefsList;
- (NSArray *)getSuperRefsList;

@end

NS_ASSUME_NONNULL_END
