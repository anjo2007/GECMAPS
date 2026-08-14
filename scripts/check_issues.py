import os, re

def check_dart_file(filepath):
    issues = []
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
    
    content = ''.join(lines)
    
    # Check for unhandled exceptions, syntax patterns, undefined vars, etc.
    # Check if any TODOs or FIXMEs exist
    for idx, line in enumerate(lines, 1):
        if 'TODO' in line or 'FIXME' in line or 'BUG' in line or 'error' in line.lower():
            issues.append((idx, line.strip()))
    return issues

for root, dirs, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            fp = os.path.join(root, f)
            iss = check_dart_file(fp)
            if iss:
                print(f"=== {fp} ({len(iss)} mentions) ===")
                for idx, line in iss[:5]:
                    print(f"  Line {idx}: {line}")
