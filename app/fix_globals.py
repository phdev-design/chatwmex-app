import os
import sys

# 1. replace debugPrint(_.toString()); with debugPrint("Error"); globally
for root, dirs, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart'):
            path = os.path.join(root, file)
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            if 'debugPrint(_.toString());' in content:
                new_content = content.replace("debugPrint(_.toString());", "debugPrint('Error caught');")
                with open(path, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                print(f"Fixed _ error in {path}")

# 2. insert mounted checks in contact_info_page.dart
target_lines = [817, 827, 831, 873, 874, 882, 890, 922, 925, 929, 937, 1041, 1070, 1089, 1090, 1093, 1097, 1098, 1137, 1142, 1146]

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
