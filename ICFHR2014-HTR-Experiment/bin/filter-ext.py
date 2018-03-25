#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys, os, argparse
import unicodedata as ud

#pname = str(sys.argv[0])
#pos = int(str(sys.argv[1]))-1

def rmdiacritics(char):
    '''
    Return the base character of char, by "removing" any
    diacritics like accents or curls and strokes and the like.
    '''
    #print(char,str(char)); print(ud.name(str(char)))
    desc = ud.name(str(char))
    cutoff = desc.find(' WITH ')
    if cutoff != -1:
        desc = desc[:cutoff]
    return ud.lookup(desc)

def getLstChars(ln):
    buf = u""
    first=True
    for c in ln:
        #print(c,c.encode(),ud.name(c),ud.category(c))
        if (not ud.category(c).startswith('M') or first) and not ud.category(c).startswith('Cc'):
            buf += rmdiacritics(c)
    #print(buf.encode('utf-8'))
        first=False
    return buf
                                                                    
def getLstCharsSepWithoutMod(ln,sp):
    buf = u""
    first=True
    for c in ln:
        #print(c,c.encode(),ud.name(c),ud.category(c))
        if ud.category(c).startswith('M') or first or ud.category(c).startswith('Cc'):
            buf += c
        else:
            if (c==' '): buf += ' '+sp
            else: buf += ' '+c
    #print(buf.encode('utf-8'))
        first=False
    return buf
                                                                    


if __name__ == '__main__':

    parser = argparse.ArgumentParser(
        description='Remove diacrtics and transform to uppercase a given input text.')
    parser.add_argument('--sepsym', type=str, default='',
                        help='Separate a given string into corresponding symbols')
    parser.add_argument('pos', type=int, default=0,
                        help='Positional token to start applying the filter')
    parser.add_argument('input', type=argparse.FileType('r'),
                        nargs='?', default=sys.stdin,
                        help='Input file')
    parser.add_argument('output', type=argparse.FileType('w'),
                        nargs='?', default=sys.stdout,
                        help='Output file')
    args = parser.parse_args()
    #print(args.pos)
    #print(args.input)
    #fin = open(args.input, 'r') 
    sep = args.sepsym
    pos = args.pos
    fin = args.input

    #for line in sys.stdin:
    for line in fin:
        line=line.strip()
        pIDs = ' '.join(line.split()[:pos])
        pText = ' '.join(line.split()[pos:])
        #print(line,pIDs)
        if (sep==''):
            if pos>0:
                print(pIDs,getLstChars(pText).upper())
            else: print(getLstChars(pText).upper())
        else:
            if args.pos>0:
                print(pIDs,getLstCharsSepWithoutMod(pText,sep))
            else: print(getLstCharsSepWithoutMod(pText,sep))
        #print(rmdiacritics(line))

sys.exit(os.EX_OK)
