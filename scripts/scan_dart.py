import os, re

lib_dir = 'lib'

all_dart_files = []
for root, dirs, files in os.walk(lib_dir):
    for f in files:
        if f.endswith('.dart'):
            all_dart_files.append(os.path.join(root, f))

print(f"Found {len(all_dart_files)} Dart files:")
for f in sorted(all_dart_files):
    with open(f, 'r', encoding='utf-8') as fh:
        lines = fh.readlines()
    print(f"  {f}: {len(lines)} lines")
