# Examples

Two of them. One is the field itself, and needs a device or a browser. The other
is a plain Dart script that needs neither, and answers the question the README's
"What the grid costs" section raises: what does the spatial grid actually buy?

## What the connecting-line pass costs

```sh
cd example
dart run frame_cost.dart
```

Every frame, a constellation field has to decide which pairs of particles are
close enough to draw a line between. Asking every pair is `n(n-1)/2` distance
checks; this package buckets particles into a grid whose cell size is the
connection distance, so a particle only looks at its own cell and the eight
around it. The script runs both passes over the same field, requires them to
have drawn the same number of lines, and times them. Before any of that it
checks the property the grid rests on (that every pair inside the connection
distance really is in the nine cells around it) and then re-runs that check
against a deliberately broken grid to confirm the check can fail at all.

It reports three columns, because there turned out to be three answers: every
pair, the grid as the widget's painter walks it, and the same grid walked
without the per-particle candidate list that `getNearby` builds.

### Raising the count on a fixed 1200x800 canvas

The thing people actually do: a background sized to the window, and a
`particleCount` turned up until it looks right.

```
            distance checks          microseconds per pass
       n      pair      grid       pair    grid  in place     links
      50      1225       197        0.8     6.7       3.8        76
     100      4950       759        3.0    16.9       9.1       290
     200     19900      2532       12.5    41.2      17.3       977
     400     79800      9584       60.3   115.7      40.2      3563
     800    319600     36861      273.6   395.3     107.0     13611
    1600   1279200    144288     1199.1  1605.1     543.6     54180
```

The check columns are the ones to trust: they are arithmetic over a fixed seed
and will come out the same on your machine. At 800 particles the grid asks
36,861 distance questions where every pair asks 319,600, which is the whole of
what the grid was built to do, and it does it.

The time columns are where it gets interesting, and they are honest rather than
flattering. **The grid column, which is the pass the widget actually runs, is
the slower of the two at every population in that table.** A distance check is about
a nanosecond of arithmetic. At 800 particles the grid removes seven of every
eight of them and puts nine hash-map lookups per particle, plus a full rebuild
every frame, in their place. Fewer operations is not the same as less time.

The third column locates the rest of it. `getNearby` allocates a fresh list per
particle and copies every index in nine cells into it, roughly twice the
candidate count, which is the very thing the grid exists to reduce. Walking
those cells where they sit instead, same cells and same answer, is the only
column that ever comes out ahead: it wins from about 400 particles up and loses
below that.

### The same counts, canvas growing with them

Four times the particles on twice the canvas in each direction, so a particle's
neighbourhood stays about as crowded as it started. This is the configuration in
which a spatial grid is asymptotically better rather than better by a constant,
and it is the one usually meant when someone calls such a pass "close to O(n)".

```
            distance checks          microseconds per pass
       n     canvas      pair      grid       pair      grid     links
     100   1200x800      4950       759        3.8      15.4       290
     400  2400x1600     79800      2567       55.3      60.0       954
    1600  4800x3200   1279200     10181      768.8     286.9      3752
    6400  9600x6400  20476800     42241    11889.5    2029.6     14903
```

Each step multiplies the count by four. Every-pair's checks go up sixteen times
per step; the grid's go up about four. That is a difference in shape rather than
a constant factor, and here the wall clock follows it: the crossover lands
between 400 and 1600 particles, and by 6400 the gap is roughly fivefold, with
the candidate list left in. (That ratio moved between 4.5 and 5.9 across runs on
the same machine, which is a fair reminder of what these columns are worth.)

Both tables are true, and together they say something more useful than either
alone: **the grid bounds a particle's work by how crowded its neighbourhood is,
not by how many particles exist.** On a canvas that grows with the count that is
an order of magnitude. On a canvas that stays put it is a constant factor, and
the bookkeeping can eat it.

![Two log-log panels of distance checks per frame. On the fixed canvas both passes have slope 2 and the grid line runs parallel below all-pairs. On the growing canvas the grid drops to slope 1 while all-pairs stays at 2.](https://raw.githubusercontent.com/Yusufihsangorgel/constellation_particles/main/doc/benchmark.png)

That chart is the check columns of both tables above, drawn on log-log axes by
`dart run tool/benchmark_chart.dart`, which runs this script and plots what it
prints. It leaves the microsecond columns out on purpose: the check counts are
arithmetic over a fixed seed and reproduce anywhere, while the timings move
with the machine.

### Measure the mode you ship

`dart run` gives you the JIT. A Flutter release build is AOT-compiled, and the
map-heavy code fares worse there by enough to change the answer:

```sh
cd example
dart compile exe frame_cost.dart -o frame_cost && ./frame_cost
```

```
       n      pair      grid       pair    grid  in place     links
      50      1225       197        1.1     8.4       7.2        76
     100      4950       759        4.6    21.9      17.2       290
     200     19900      2532       21.0    60.1      48.6       977
     400     79800      9584       91.2   162.5     141.1      3563
     800    319600     36861      368.5   522.6     498.4     13611
    1600   1279200    144288     1501.5  1870.7    1685.9     54180
```

Under AOT, on a fixed canvas, both grid columns lose at every population in that
table, including the one without the allocation. Three runs agreed on the
ordering. All the timings on this page are one arm64 laptop on Dart 3.11.0,
each the fastest of three rounds after a warm-up. Yours will differ; the point
is that the ordering here is not a constant of nature, so if it matters to you,
run it where you ship.

### What none of it measures

The neighbour pass, and only the neighbour pass. The widget then draws what the
pass found, and at 800 particles on the fixed canvas that was 13,611 links:
13,611 `drawLine` calls a frame, each with its own colour, plus a circle per
particle and a fresh radial gradient for the larger ones. Which of those you
would actually feel as a dropped frame is not a question this script answers,
and a Flutter timeline is the right instrument for that one.

So the practical reading, for someone deciding whether to use this widget: at a
few hundred particles on a normal window, neither pass is anywhere near a frame
budget, since both are under a millisecond, and what you should be sizing is the
number of *lines* you are asking the GPU to draw. The particle count controls
that quadratically. 400 particles is 3,563 lines; 800 is 13,611.

## The field itself

```sh
cd example
flutter run
```

A dark page with a 140-particle field behind it. Move the cursor and the
particles get out of its way; the repulsion is driven by `MouseRegion`, so on a
phone the field just drifts unless you pass `touchReactive: true`.

Two things worth trying, because both are easy to get wrong in your own app:

- Turn on reduce-motion in the OS while it runs. The constellation stays,
  the drift stops. That is deliberate: hiding the widget would be a worse
  answer to a request for less motion than holding it still.
- Turn on high contrast. The particle count halves.

## A note on the cell size

The script's last section demonstrates the one thing in the grid that must not
be tuned. Its cell size equals the connection distance, and that is what makes
nine cells enough: two particles closer together than one cell size cannot be
two cells apart. Halve the cells and the pass gets *faster* while silently
dropping a third of the lines: at 400 particles, 1,091 of 3,563. Larger cells
stay correct and only cost more. Smaller ones are a rendering bug that profiles
well, which is the hardest kind to notice.
