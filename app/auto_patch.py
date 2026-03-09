import os
import subprocess
import re

file_path = 'lib/features/chat/ui/contact_info_page.dart'

def patch_file():
    print("Running flutter analyze...")
    result = subprocess.run(['flutter', 'analyze'], capture_output=True, text=True)
    
    # find lines for contact_info_page
    lines_to_patch = []
    for line in result.stdout.split('\n'):
        if 'use_build_context_synchronously' in line and file_path in line:
            # Extract line number
            match = re.search(r'contact_info_page\.dart:(\d+):', line)
            if match:
                lines_to_patch.append(int(match.group(1)))
                
    if not lines_to_patch:
        print("No more use_build_context_synchronously found!")
        return False
        
    lines_to_patch = sorted(list(set(lines_to_patch)), reverse=True)
    print(f"Patching lines: {lines_to_patch}")
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content_lines = f.read().split('\n')
        
    for lineno in lines_to_patch:
        idx = lineno - 1
        prev_idx = idx - 1
        if prev_idx >= 0 and 'mounted' in content_lines[prev_idx]:
            continue
            
        indent = len(content_lines[idx]) - len(content_lines[idx].lstrip())
        prefix = ' ' * indent
        content_lines.insert(idx, prefix + "if (!mounted) return;")
        
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(content_lines))
        
    return True

# Loop until fixed
while patch_file():
    pass
