"""Build one offline Lua installer and refresh the distribution zip."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).parent

def lua_string(value):
    delimiter = '='
    while ']' + delimiter + ']' in value:
        delimiter += '='
    # Lua discards the first newline following a long-bracket opener.
    return '[' + delimiter + '[\n' + value + ']' + delimiter + ']'

items = [(name, (root / name).read_text(encoding='utf-8')) for name in
         ('diskdesk.lua', 'diskdesk_services.lua', 'diskdesk_arrays.lua')]
items.append(('launcher', '-- DiskDesk launcher\nshell.run("/diskdesk-app/diskdesk.lua", ...)\n'))
payload = '\n'.join('  {name=' + lua_string(name) + ', contents=' + lua_string(contents) + '},'
                    for name, contents in items)
template = (root / 'installer_template.lua').read_text(encoding='utf-8')
assert template.count('-- DISKDESK_PAYLOAD') == 1
(root / 'instalar_diskdesk.lua').write_text(
    template.replace('-- DISKDESK_PAYLOAD', payload), encoding='utf-8', newline='\n')

distribution = ('instalar_diskdesk.lua', 'diskdesk.lua', 'diskdesk_services.lua', 'diskdesk_arrays.lua',
                'README.md', 'IDEIAS.md', 'GITHUB.md')
source = distribution + ('build_installer.py', 'installer_template.lua', '.gitignore',
                         'test_diskdesk.py', 'test_services.py', 'test_installer.py', 'test_arrays.py',
                         'render_preview.py')
for filename, files in (('DiskDesk-3.zip', distribution), ('DiskDesk-GitHub.zip', source)):
    with ZipFile(root / filename, 'w', ZIP_DEFLATED) as archive:
        for name in files:
            archive.write(root / name, name)
    with ZipFile(root / filename) as archive:
        assert archive.testzip() is None
        for name in archive.namelist():
            assert archive.read(name) == (root / name).read_bytes()
print('Instalador offline e pacote ZIP gerados e verificados.')
