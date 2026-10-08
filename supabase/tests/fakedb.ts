// Minimal supabase-js look-alike over PGlite — just enough of the query
// builder for _shared/booking.ts, so its real logic runs against real SQL.
import { PGlite } from "npm:@electric-sql/pglite@0.3";

type Res = { data: any; error: any };
const ident = (s: string) => '"' + s.replace(/"/g, '""') + '"';

class Query implements PromiseLike<Res> {
  private wheres: string[] = [];
  private params: unknown[] = [];
  private orders: string[] = [];
  private lim: number | null = null;
  private mode: "select" | "insert" | "update" = "select";
  private cols = "*";
  private returning: string | null = null;
  private row: Record<string, unknown> = {};
  private one: "single" | "maybe" | null = null;
  constructor(private pg: PGlite, private table: string) {}
  private p(v: unknown, raw = false) {
    this.params.push(!raw && v !== null && typeof v === "object" ? JSON.stringify(v) : v);
    return `$${this.params.length}`;
  }
  select(cols = "*") {
    if (this.mode === "select") this.cols = cols;
    else this.returning = cols;
    return this;
  }
  insert(row: Record<string, unknown>) { this.mode = "insert"; this.row = row; return this; }
  update(row: Record<string, unknown>) { this.mode = "update"; this.row = row; return this; }
  eq(c: string, v: unknown) { this.wheres.push(`${ident(c)}::text = ${this.p(v)}::text`); return this; }
  in(c: string, vs: unknown[]) { this.wheres.push(`${ident(c)}::text = any(${this.p(vs.map(String), true)}::text[])`); return this; }
  order(c: string, o?: { ascending?: boolean }) { this.orders.push(`${ident(c)} ${o?.ascending === false ? "desc" : "asc"}`); return this; }
  limit(n: number) { this.lim = n; return this; }
  single() { this.one = "single"; return this; }
  maybeSingle() { this.one = "maybe"; return this; }
  private sql(): string {
    const where = this.wheres.length ? " where " + this.wheres.join(" and ") : "";
    const colList = (c: string) => c === "*" ? "*" : c.split(",").map((x) => ident(x.trim())).join(",");
    if (this.mode === "select") {
      return `select ${colList(this.cols)} from ${ident(this.table)}${where}` +
        (this.orders.length ? " order by " + this.orders.join(",") : "") + (this.lim !== null ? ` limit ${this.lim}` : "");
    }
    const keys = Object.keys(this.row);
    if (this.mode === "insert") {
      const vals = keys.map((k) => this.p(this.row[k]));
      return `insert into ${ident(this.table)} (${keys.map(ident).join(",")}) values (${vals.join(",")})` +
        (this.returning ? ` returning ${colList(this.returning)}` : "");
    }
    const sets = keys.map((k) => `${ident(k)} = ${this.p(this.row[k])}`);
    return `update ${ident(this.table)} set ${sets.join(",")}${where}`;
  }
  async run(): Promise<Res> {
    try {
      const r = await this.pg.query(this.sql(), this.params);
      let data: any = r.rows;
      if (this.one) {
        if (data.length > 1 || (this.one === "single" && data.length === 0)) {
          return { data: null, error: { message: `expected one row, got ${data.length}` } };
        }
        data = data[0] ?? null;
      }
      return { data, error: null };
    } catch (e) {
      return { data: null, error: { message: (e as Error).message } };
    }
  }
  then<A, B>(ok?: (v: Res) => A | PromiseLike<A>, err?: (e: unknown) => B | PromiseLike<B>) {
    return this.run().then(ok, err);
  }
}

export function fakeDb(pg: PGlite) {
  return {
    from: (t: string) => new Query(pg, t),
    rpc: async (fn: string, args: Record<string, unknown>) => {
      const keys = Object.keys(args);
      try {
        const r = await pg.query(`select * from ${ident(fn)}(${keys.map((k, i) => `${ident(k)} => $${i + 1}`).join(",")})`,
          keys.map((k) => args[k]));
        // scalar functions come back as a single column named after the function
        const rows = r.rows as any[];
        if (rows.length === 1 && Object.keys(rows[0]).length === 1 && fn in rows[0]) return { data: rows[0][fn], error: null };
        return { data: rows, error: null };
      } catch (e) {
        return { data: null, error: { message: (e as Error).message } };
      }
    },
  };
}
