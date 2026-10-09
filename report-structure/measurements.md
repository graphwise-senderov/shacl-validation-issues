| capture      | form     | results | triples | triples per result | rsx triples | N-Triples bytes |
|--------------|----------|--------:|--------:|-------------------:|------------:|----------------:|
| single-graph | as-is    |      10 |     105 |     8 (x4), 9 (x6) |          20 |           12829 |
| single-graph | proposed |      10 |      87 |     6 (x4), 7 (x6) |           2 |           10579 |
| repeat       | as-is    |      10 |     159 |                 14 |          60 |           19234 |
| repeat       | proposed |      10 |     105 |                  8 |           6 |           12790 |
| fanout       | as-is    |     100 |    5906 |                 58 |        5100 |          710245 |
| fanout       | proposed |     100 |     857 |                  7 |          51 |          104266 |
| logic        | as-is    |       4 |      81 |                  9 |           8 |            9618 |
| logic        | proposed |       4 |      75 |                  7 |           2 |            8910 |
