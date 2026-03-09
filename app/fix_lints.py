import os
import re

def process_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    orig_content = content

    # Fix avoid_print
    content = re.sub(r'(?<!\.)\bprint\(', 'debugPrint(', content)
    
    # Fix empty_catches: catch (e) {} -> catch (e) { debugPrint(e.toString()); }
    content = re.sub(r'catch\s*\(([^)]+)\)\s*\{\s*\}', r'catch (\1) { debugPrint(\1.toString()); }', content)
    
    # Needs foundation import if we added debugPrint
    if 'debugPrint(' in content and 'import \'package:flutter/foundation.dart\';' not in content:
        # insert at top
        content = "import 'package:flutter/foundation.dart';\n" + content

    if content != orig_content:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Fixed prints/catches in {path}")

for root, dirs, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart'):
            process_file(os.path.join(root, file))

