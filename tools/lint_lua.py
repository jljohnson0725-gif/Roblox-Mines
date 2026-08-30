import io,re,sys,glob
Q=chr(34); NL=chr(10)
def clean(s):
    # 1. long comments
    out,i=[],0
    while True:
        j=s.find("--[[",i)
        if j<0: out.append(s[i:]);break
        out.append(s[i:j]); k=s.find("]]",j)
        if k<0: return None
        i=k+2
    c="".join(out)
    # 2. STRINGS BEFORE LINE COMMENTS -- a string may legitimately contain "--"
    c=re.sub(Q+'[^'+Q+NL+']*'+Q,' S ',c)
    c=re.sub(chr(39)+'[^'+chr(39)+NL+']*'+chr(39),' S ',c)
    # 3. line comments, now that no "--" inside a string survives
    c=re.sub('--.*','',c)
    return c
bad=0
for f in sorted(glob.glob("src/**/*.lua",recursive=True)):
    c=clean(io.open(f,encoding="utf-8").read())
    if c is None:
        print("UNCLOSED --[[ : "+f); bad+=1; continue
    br=c.count("{")-c.count("}"); pr=c.count("(")-c.count(")")
    kw=len(re.findall(r'\b(function|for|if|while)\b',c))-len(re.findall(r'\bend\b',c))
    if br or pr or kw:
        print("%-44s braces %+d parens %+d block %+d"%(f.split("src/")[-1],br,pr,kw)); bad+=1
print("\n%d of %d files flagged"%(bad,len(glob.glob("src/**/*.lua",recursive=True))))
