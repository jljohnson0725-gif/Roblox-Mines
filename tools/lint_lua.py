"""Balance and string checks across every Lua file in src/.

Order matters: STRINGS ARE STRIPPED BEFORE LINE COMMENTS. Doing it the other
way round eats the rest of any line holding a string that contains "--", which
produces phantom unbalanced braces -- it did, twice.

The unterminated-string check is the one that actually earns its keep: a line
edit that writes a real newline where "\n" was meant produces a syntax error
that brace counting cannot see, and it took down Bootstrap once.
"""
import io, re, sys, glob

Q, NL, SQ = chr(34), chr(10), chr(39)

def strip_long_comments(s):
    """Blank long comments out IN PLACE, keeping their newlines, so every
    reported line number still points at the real file. Deleting them shifts
    everything below and sends you to the wrong line."""
    out, i = [], 0
    while True:
        j = s.find("--[[", i)
        if j < 0:
            out.append(s[i:]); return "".join(out)
        out.append(s[i:j])
        k = s.find("]]", j)
        if k < 0:
            return None
        out.append(NL * s.count(NL, j, k + 2))
        i = k + 2

def clean(s):
    c = strip_long_comments(s)
    if c is None:
        return None
    c = re.sub(Q + '[^' + Q + NL + ']*' + Q, ' S ', c)
    c = re.sub(SQ + '[^' + SQ + NL + ']*' + SQ, ' S ', c)
    return re.sub('--.*', '', c)

def unterminated(code):
    """lines where a quote opens and never closes before the newline"""
    bad = []
    for n, line in enumerate(code.split(NL), 1):
        depth, esc = 0, False
        for ch in line:
            if esc:
                esc = False; continue
            if ch == chr(92):
                esc = True; continue
            if ch == Q:
                depth = 1 - depth
        if depth:
            bad.append((n, line.strip()[:70]))
    return bad

def main():
    files = sorted(glob.glob("src/**/*.lua", recursive=True))
    flagged = 0
    for f in files:
        raw = io.open(f, encoding="utf-8").read()
        c = clean(raw)
        if c is None:
            print("UNCLOSED --[[  " + f); flagged += 1; continue
        # unterminated strings are checked on comment-stripped-but-string-KEPT text
        kept = strip_long_comments(raw)
        kept = kept.replace('--' + chr(91) + chr(91), '')
        for n, line in unterminated(kept):
            if line.startswith("--"):
                continue
            print("%s:%d  string runs off the end of the line" % (f, n))
            print("      " + line); flagged += 1
        br = c.count("{") - c.count("}")
        pr = c.count("(") - c.count(")")
        kw = len(re.findall(r'\b(function|for|if|while)\b', c)) - len(re.findall(r'\bend\b', c))
        if br or pr or kw not in (0, -1):
            print("%-46s braces %+d parens %+d block %+d" % (f, br, pr, kw)); flagged += 1
    print("\n%d issue(s) across %d files" % (flagged, len(files)))
    return 1 if flagged else 0

sys.exit(main())
