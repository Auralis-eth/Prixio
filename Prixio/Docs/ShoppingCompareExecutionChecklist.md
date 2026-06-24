# Shopping Compare Execution Checklist (retired)

The Compare + Shopping List MVP this checklist drove has shipped and is covered by code and tests, so
this planning doc is kept only as a redirect.

- **What it built** (Compare browse/search/detail, Shopping List checklist + trip optimizer, the
  shared `PriceInsightEngine`/`ItemKeyNormalizer` domain, and the scan-nudge freshness loop) is
  described in `LLMAppContext.md` → **Compare Flow**, **Shopping List Flow**, and **Shared Derived
  Domain**, with the matching suites in its **Testing Map**.
- **Locked product decisions** that outlived the checklist — tab order (`Scan / Compare / Shopping
  List / Settings`), the multi-list-ready data model behind one visible default list, and the
  row-best-store-first → trip-winner-fallback scan prefill — live in `LLMAppContext.md`
  (architecture + Known Gotchas). Note the original "Compare detail = delete only" decision has since
  been superseded by entry editing (defect B8).
- **Remaining post-MVP polish** (single visible list, end-to-end row distance, trip-plan breakdown UI,
  the B4 repository-parity advisory): `OutstandingWork.md` → **item 5**.

Per `OutstandingWork.md`, that file replaces older planning/checklist markdown like this one.
