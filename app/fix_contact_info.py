import os
import sys

# output from flutter analyze:
target_lines = [
  814, 824, 828, 870, 871, 879, 887, 919, 922, 926, 934, 1038, 1067, 1086, 1087, 1090, 1094, 1095, 1134, 1139, 1143
]

file_path = 'lib/features/chat/ui/contact_info_page.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.read().split('\n')

# We apply in reverse to not mess up previous line numbers
target_lines = sorted(list(set(target_lines)), reverse=True)

for lineno in target_lines:
    # 0 indexed
    idx = lineno - 1
    
    # check if there's already mounted check
    prev_idx = idx - 1
    if prev_idx >= 0 and 'mounted' in lines[prev_idx]:
        continue
        
    # get indentation
    indent = len(lines[idx]) - len(lines[idx].lstrip())
    prefix = ' ' * indent
    
    lines.insert(idx, prefix + "if (!mounted) return;")

with open(file_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))
    
print('Inserted mounted checks in contact_info_page.dart')
