# Trellis query timings

Measured on 23 November 2026 using PostgreSQL 17.11 (Homebrew) and Prisma 6.19.3. The database was initialized with the repo’s migrations and topic seed. It contained 3 subjects, 43 topics, 56 prerequisite links, 1000 synthetic users, 1000 synthetic refresh tokens, and 8000 synthetic progress rows (eight per user). PostgreSQL statistics were collected with `ANALYZE` after loading the fixtures.

The table covers SQL statements emitted by Prisma for the backend and maintenance scripts. It lists shared reads once for identical SQL with representative inputs. Relation loads that Prisma sends separately have their own rows. The progress upsert is measured with both an existing row and a missing row.

Each query ran three times on a local database with the default planner settings and no cache reset between runs. The numbers are the reported PostgreSQL execution times in milliseconds, averaged and rounded to three decimal places. Planning time, network latency, and application work such as bcrypt, topic sorting, and Groq calls are outside these timings. Each run used a transaction that was rolled back. Scan types are taken from the plan nodes, including scans inside writes when present.

| Query | Type | What it does | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Scan type |
| :---- | :--- | :----------- | ---------: | ---------: | ---------: | -----------: | :-------- |
| [R1](plans/R1.txt) | READ | Find user by email for login, signup, or Google account linking | 0.032 | 0.008 | 0.007 | 0.016 | Index Scan |
| [R2](plans/R2.txt) | READ | Load the signed-in user by ID | 0.018 | 0.004 | 0.003 | 0.008 | Index Scan |
| [R3](plans/R3.txt) | READ | Find a returning Google user by Google ID | 0.021 | 0.004 | 0.003 | 0.009 | Index Scan |
| [R4](plans/R4.txt) | READ | Find a refresh token by hash | 0.011 | 0.005 | 0.003 | 0.006 | Index Scan |
| [R5](plans/R5.txt) | READ | Load the refresh token’s user | 0.023 | 0.004 | 0.005 | 0.011 | Index Scan |
| [R6](plans/R6.txt) | READ | List subjects with topic counts | 0.040 | 0.017 | 0.014 | 0.024 | Seq Scan |
| [R7](plans/R7.txt) | READ | Find a subject by ID | 0.010 | 0.004 | 0.003 | 0.006 | Seq Scan |
| [R8](plans/R8.txt) | READ | List topics in a subject | 0.012 | 0.004 | 0.005 | 0.007 | Seq Scan |
| [R9](plans/R9.txt) | READ | Load prerequisite links for the subject’s topics | 0.015 | 0.006 | 0.005 | 0.009 | Seq Scan |
| [R10](plans/R10.txt) | READ | Find a topic by ID | 0.011 | 0.003 | 0.003 | 0.006 | Seq Scan |
| [R11](plans/R11.txt) | READ | Load prerequisite links for one topic | 0.010 | 0.004 | 0.004 | 0.006 | Seq Scan |
| [R12](plans/R12.txt) | READ | Load the prerequisite topic records | 0.013 | 0.005 | 0.004 | 0.007 | Seq Scan |
| [R13](plans/R13.txt) | READ | Load the prompt topic’s subject | 0.010 | 0.002 | 0.003 | 0.005 | Seq Scan |
| [R14](plans/R14.txt) | READ | Read the progress fields shown on the map | 0.033 | 0.008 | 0.007 | 0.016 | Index Scan |
| [R15](plans/R15.txt) | READ | Read progress rows for next-topic selection | 0.032 | 0.009 | 0.006 | 0.016 | Index Scan |
| [R16](plans/R16.txt) | READ | Read progress by topic IDs for stuck hints | 0.016 | 0.004 | 0.004 | 0.008 | Index Scan |
| [R17](plans/R17.txt) | READ | Read progress for the prompt topic and its prerequisites | 0.018 | 0.004 | 0.004 | 0.009 | Index Scan |
| [W1](plans/W1.txt) | WRITE | Create a password account | 0.134 | 0.011 | 0.762 | 0.302 | — |
| [W2](plans/W2.txt) | WRITE | Create a Google account | 0.105 | 0.013 | 0.011 | 0.043 | — |
| [W3](plans/W3.txt) | WRITE | Link Google to an existing user | 0.103 | 0.016 | 0.013 | 0.044 | Index Scan |
| [W4](plans/W4.txt) | WRITE | Issue a refresh token | 0.327 | 0.037 | 0.021 | 0.128 | — |
| [W5](plans/W5.txt) | WRITE | Mark an unused refresh token as used | 0.102 | 0.017 | 0.014 | 0.044 | Index Scan |
| [W6](plans/W6.txt) | WRITE | Delete a refresh token on logout | 0.046 | 0.007 | 0.008 | 0.020 | Index Scan |
| [W7](plans/W7.txt) | WRITE | Create a topic in the admin editor | 0.268 | 0.025 | 0.020 | 0.104 | — |
| [W8](plans/W8.txt) | WRITE | Edit a topic in the admin editor | 0.068 | 0.015 | 0.011 | 0.031 | Seq Scan |
| [W9](plans/W9.txt) | WRITE | Delete a topic’s prerequisite links before replacing them | 0.045 | 0.009 | 0.007 | 0.020 | Seq Scan |
| [W10](plans/W10.txt) | WRITE | Insert a topic’s prerequisite links in the admin editor | 0.333 | 0.049 | 0.037 | 0.140 | Values Scan |
| [W11](plans/W11.txt) | WRITE | Upsert progress on the update path with a note | 0.171 | 0.020 | 0.019 | 0.070 | — |
| [W12](plans/W12.txt) | WRITE | Upsert progress on the insert path | 0.377 | 0.037 | 0.029 | 0.148 | — |
| [W13](plans/W13.txt) | WRITE | Upsert progress on the update path with the note omitted | 0.130 | 0.016 | 0.013 | 0.053 | — |
| [W14](plans/W14.txt) | WRITE | Promote a user to admin by email (make-admin script) | 0.102 | 0.017 | 0.011 | 0.043 | Index Scan |
| [W15](plans/W15.txt) | WRITE | Upsert an existing subject by slug (seed script) | 0.082 | 0.011 | 0.009 | 0.034 | — |
| [W16](plans/W16.txt) | WRITE | Upsert an existing topic by subject and slug (seed script) | 0.098 | 0.014 | 0.010 | 0.041 | — |
| [W17](plans/W17.txt) | WRITE | Delete prerequisite links for a subject (seed script) | 0.068 | 0.024 | 0.016 | 0.036 | Seq Scan |
| [W18](plans/W18.txt) | WRITE | Bulk insert prerequisite links for a subject (seed script) | 0.206 | 0.089 | 0.082 | 0.126 | Values Scan |
