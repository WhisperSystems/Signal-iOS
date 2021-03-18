#!/usr/bin/env python
from __future__ import print_function
import sys
import os
import re
import commands
import subprocess
import io

def fail(message):
    print(message)
    sys.exit(1)

# For simplicity and compactness, we pre-define the 
# emoji code planes to ensure that all of the currently-used
# emoji ranges within them are combined.
big_ranges = [
        (0x1F600,0x1F64F, ),
        (0x1F300,0x1F5FF, ),
        (0x1F680,0x1F6FF, ),
        (0x2600,0x26FF,   ),
        (0x2700,0x27BF,   ),
        (0xFE00,0xFE0F,   ),
        (0x1F900,0x1F9FF,  ),
        (65024,65039,), 
        (8400, 8447,)
        ]

if __name__ == '__main__':
    src_filename = "emoji-data.txt"
    src_dir_path = os.path.dirname(__file__)
    src_file_path = os.path.join(src_dir_path, src_filename)
    print('src_file_path', src_file_path)
    if not os.path.exists(src_file_path):
        fail("Could not find input file")
    
    with io.open(src_file_path, "r", encoding="utf-8") as f:
        text = f.read()
    
    lines = text.split('\n')
    raw_ranges = []
    for line in lines:
        if '#' in line:
            line = line[:line.index('#')].strip()
        if ';' not in line:
            continue
        print('line:', line)
        range_text = line[:line.index(';')]
        print('\t:', range_text)
        if '..' in range_text:
            range_start_hex_string, range_end_hex_string = range_text.split('..')
        else:
            range_start_hex_string = range_end_hex_string = range_text.strip()
        range_start = int(range_start_hex_string.strip(), 16)
        range_end = int(range_end_hex_string.strip(), 16)
        print('\t', range_start, range_end)
        
        raw_ranges.append((range_start, range_end,))
        
    raw_ranges += big_ranges
        
    raw_ranges.sort(key=lambda a:a[0])


    new_ranges = []
    for range_start, range_end in raw_ranges:
        if len(new_ranges) > 0:
            last_range = new_ranges[-1]
            # print 'last_range', last_range
            last_range_start, last_range_end = last_range
            if range_start >= last_range_start and range_start <= last_range_end + 1:
            # if last_range_end + 1 == range_start:
                new_ranges = new_ranges[:-1]
                print('merging', last_range_start, last_range_end, 'and', range_start, range_end)
                new_ranges.append((last_range_start, max(range_end, last_range_end),))
                continue

        new_ranges.append((range_start, range_end,))
    
    print()
    for range_start, range_end in new_ranges:
        # print '0x%X...0x%X, // %d Emotions' % (range_start, range_end, (1 + range_end - range_start), )
        print('EmojiRange(rangeStart:0x%X, rangeEnd:0x%X),' % (range_start, range_end, ))
    print('new_ranges:', len(new_ranges))
    print()
    print('Copy and paste the code above into DisplayableText.swift')
    print() 
        
        
