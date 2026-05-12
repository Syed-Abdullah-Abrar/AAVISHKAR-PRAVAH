#!/usr/bin/env python3
import fitz
import sys

doc = fitz.open('9789240080591-eng.pdf')
text = ''.join([page.get_text() for page in doc])
lines = text.split('\n')

print('=== FIRST 60 CONTENT LINES ===')
for l in lines[:60]:
    if l.strip():
        print(l[:120])

print()
print('=== OBSTETRIC/MATERNAL HISTORY SECTIONS ===')
keywords = ['previous pregnancy', 'birth history', 'obstetric history', 'parity', 'gravida', 
           'live birth', 'stillbirth', 'abortion', 'menstrual history', 'contraception',
           'medical history', 'surgical history', 'family history']

found = []
for i, l in enumerate(lines):
    if len(l.strip()) > 15 and any(kw in l.lower() for kw in keywords):
        found.append(f'[{i}] {l[:100]}')

for f in found[:30]:
    print(f)

print(f'\nTotal lines: {len(lines)}')
print(f'Pages: {len(doc)}')