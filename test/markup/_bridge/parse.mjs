#!/usr/bin/env node
// Batch dtext parser bridge.
//
// Protocol:
//   - Reads framed requests from stdin. Each request is a single line of JSON:
//       {"id": "<string>", "input": "<dtext source>"}              // parse
//       {"id": "<string>", "input": "<dtext>", "measure": <int>}   // bench
//     A line "EXIT" cleanly terminates the process.
//   - For every request, writes a single line of JSON to stdout:
//       {"id": "<string>", "ast": <node>}            // parse OK
//       {"id": "<string>", "micros": <int>}          // measure OK
//       {"id": "<string>", "error": "<message>"}     // parse threw
//
//   The `measure` variant runs parseDTextToAST in a tight loop N times and
//   reports total wall-clock microseconds via process.hrtime.bigint(). This
//   keeps benchmark numbers free of IPC overhead: the Dart side only pays
//   one round-trip per (input, iterations) pair.
//
// Why line-framed instead of one giant array: lets the Dart side stream
// thousands of inputs through a single long-lived Node process without
// holding the whole batch in memory on either side.

import { createInterface } from 'node:readline';
import { parseDTextToAST } from 'dmark';

const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });

function write(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

rl.on('line', (line) => {
  if (line === 'EXIT') {
    rl.close();
    return;
  }
  if (line === '') {
    return;
  }
  let req;
  try {
    req = JSON.parse(line);
  } catch (e) {
    write({ id: null, error: `bad request frame: ${e.message}` });
    return;
  }
  if (typeof req.measure === 'number' && req.measure > 0) {
    try {
      const iterations = req.measure;
      const input = req.input;
      // Warm-up pass so the first timed iteration is not JIT-cold.
      parseDTextToAST(input);
      const start = process.hrtime.bigint();
      for (let i = 0; i < iterations; i++) {
        parseDTextToAST(input);
      }
      const elapsedNanos = process.hrtime.bigint() - start;
      const micros = Number(elapsedNanos / 1000n);
      write({ id: req.id, micros });
    } catch (e) {
      write({ id: req.id, error: e?.stack ?? String(e) });
    }
    return;
  }
  try {
    const ast = parseDTextToAST(req.input);
    write({ id: req.id, ast });
  } catch (e) {
    write({ id: req.id, error: e?.stack ?? String(e) });
  }
});

rl.on('close', () => {
  process.exit(0);
});

// Surface unhandled errors instead of silently dying.
process.on('uncaughtException', (e) => {
  write({ id: null, error: `uncaught: ${e?.stack ?? String(e)}` });
  process.exit(2);
});
