# Compress Praat short text files, only extract nessecery values, to be accessed fast by lua scripts in SV

import os
import math
from pathlib import Path

def find_file(ext: str):
    '''Find *.ext under working directory'''
    glob = list(Path('.').glob('*.'+ext))
    if len(glob) == 1:
        return glob[0]
    if glob:    # len >= 2
        choices = [f' {i+1}) {p}' for i, p in enumerate(glob)]
        s = input('Choose one from\n' + '\n'.join(choices)
            + '\n(Enter a number, a substring that identifies your choice, or a path to a file elsewhere)\n')
    else:
        s = input(f'No {ext} file found at {Path(".").resolve()}\nInput a {ext} file: ')
    while True:
        if glob:
            if s.isdigit():
                x = int(s)
                if 1 <= x and x <= len(glob):
                    return glob[x-1]
            for i, choice in enumerate(choices):
                if s in choice:
                    return glob[i]
        p = Path(s.strip('\'"'))
        if p.exists():
            return p
        s = input('No such file, try again: ')


def list_jobs(ext):
    '''Return a list of (uptodate, src, dst)'''
    dst = svp_path.with_name(f'{svp_path.stem}_{ext}.txt')
    dst_time = dst.stat().st_mtime if dst.exists() else 0
    return [(src.stat().st_mtime < dst_time, src, dst) for src in Path('.').glob('*.'+ext)]


def convert(src: Path, dst: Path):
    with src.open() as fin:
        if fin.readline() != 'File type = "ooTextFile"\n': print('Format Error'); return
        line = fin.readline()
        if not line.startswith('Object class = '): print('Format Error'); return
        Object_class = eval(line[15:])
        fin.readline()
        if Object_class == 'Pitch 1':

            xmin = float(fin.readline())
            xmax = float(fin.readline())
            nx = int(fin.readline())
            dx = float(fin.readline())
            x1 = float(fin.readline())
            ceiling = float(fin.readline())
            maxnCandidates = int(fin.readline())

            pitch, is_voiced = [], []
            prev_voiced, prev = [], -1
            if nx <= 0: print('Pitch file is empty.'); return
            for i in range(nx):
                intensity = float(fin.readline())
                nCandidates = int(fin.readline())
                for j in range(nCandidates):
                    frequency = float(fin.readline())
                    strength = float(fin.readline())
                    if j == 0:
                        if freq_min < frequency and frequency < freq_max:  # voiced
                            is_voiced.append(1)
                            pitch.append(math.log(frequency / 440, 2) * 12 + 69) # in semitones
                            prev = i
                        else:
                            is_voiced.append(0)
                            pitch.append(0)
                        prev_voiced.append(prev)
            if prev == -1: print("No voiced pitch in Pitch file."); return

            # TODO: apply low-pass filter, ignoring unvoiced data, maybe using strength as weights

            # interpolate unvoiced parts
            next = -1
            for i in range(nx-1, -1, -1):
                if is_voiced[i]:
                    next = i
                else:
                    prev = prev_voiced[i]
                    if prev == -1:
                        pitch[i] = pitch[next]
                    elif next == -1:
                        pitch[i] = pitch[prev]
                    else:
                        pitch[i] = (pitch[prev] * (next - i) + pitch[next] * (i - prev)) / (next - prev)

            with dst.open('w', newline='\n') as fout:
                fout.write(f'Pitch\n{nx}\n{dx}\n{x1}\n')
                fout.write('\n'.join(f'{p:0<17.16}'[:17] for p in pitch) + '\n') # 18 chars each
                fout.write('\n'.join(str(v) for v in is_voiced) + '\n') # 2 chars each

        else: # endif Object_class 
            print('Unsupported object class: ' + Object_class)
            return
    input("Done.") # endfunction


if __name__ == '__main__':
    svp_path = find_file('svp')
    os.chdir(svp_path.parent)
    s = input('Min frequency (default 100): ')
    freq_min = float(s) if s else 100
    s = input('Max frequency (default 1000): ')
    freq_max = float(s) if s else 1000
    while True:
        jobs = list_jobs('Pitch')
        jobs.sort()
        src_len = max(len(str(src.name)) for _, src, _ in jobs)
        s = input('\nChoose a job\n' +
            '\n'.join(f' {" " if uptodate else "*"} {i+1}) {src.name.ljust(src_len)} -> {dst.name}'
                      for i, (uptodate, src, dst) in enumerate(jobs))
            + '\n(or input a file name, or <Enter> to refresh)\n')
        if s == '': continue
        if s.isdigit():
            x = int(s)
            if 1 <= x and x <= len(jobs):
                convert(*jobs[x-1][1:])
                continue
        src = Path(s.strip('\'"'))
        if src.exists():
            dst = svp_path.with_name(f'{svp_path.stem}_{src.suffix[1:]}.txt')
            confirm = input(f'{src} -> {dst}\nok? ([y]/n) ')
            if confirm == '' or confirm[0].lower() == 'y':
                convert(src, dst)