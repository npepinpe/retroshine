#!/usr/bin/env python3
"""Patch critical ES-DE settings without clobbering user preferences."""
import xml.etree.ElementTree as ET
import sys

REQUIRED = [
    ('string', 'ROMDirectory', '/games'),
    ('bool',   'WizardCompleted', 'true'),
]

path = sys.argv[1]
try:
    tree = ET.parse(path)
    root = tree.getroot()
except Exception:
    root = ET.Element('config')
    tree = ET.ElementTree(root)

changed = False
for tag, name, value in REQUIRED:
    el = root.find(f'.//{tag}[@name="{name}"]')
    if el is None:
        el = ET.SubElement(root, tag)
        el.set('name', name)
        changed = True
    if el.get('value') != value:
        el.set('value', value)
        changed = True

if changed:
    tree.write(path, xml_declaration=True, encoding='unicode')
