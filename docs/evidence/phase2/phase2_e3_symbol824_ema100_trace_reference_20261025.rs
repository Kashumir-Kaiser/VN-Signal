use std::{env, fs, process};

fn opt(v: &str) -> Option<f64> { if v == "NULL" || v.is_empty() { None } else { Some(v.parse().unwrap()) } }
fn fmt(v: Option<f64>) -> String { v.map(|x| format!("{x:.17e}")).unwrap_or_else(|| "NULL".to_owned()) }
fn rel(a: Option<f64>, b: Option<f64>) -> Option<f64> {
    match (a,b) { (None,None) => Some(0.0), (Some(x),Some(y)) => {
        let s=x.abs().max(y.abs()); Some(if s==0.0 {0.0} else {(x-y).abs()/s})
    }, _ => None }
}
fn pass(a: Option<f64>, b: Option<f64>) -> bool { rel(a,b).is_some_and(|x| x<=1e-9) }
fn main() {
    let a: Vec<String> = env::args().collect();
    if a.len()!=3 { eprintln!("usage: trace INPUT.csv OUTPUT.csv"); process::exit(2); }
    let input=fs::read_to_string(&a[1]).unwrap();
    let mut output=String::from("trade_date|session_no|bar_episode|sql_episode_key|raw_model_c|adjustment_ratio|sql_close|rust_close|sql_ema_input|sql_ema_count|rust_ema_count|sql_ema100|rust_ema100|sql_ratio|rust_ratio|stored_feature_ratio|close_rel_error|ema_rel_error|ratio_rel_error|close_within_1e9|ema_within_1e9|ratio_within_1e9\n");
    let mut cumulative_log=0.0f64;
    let mut factor_episode: Option<String>=None;
    let mut prior_episode: Option<String>=None;
    let mut ema: Option<f64>=None;
    let mut count=0usize;
    let alpha=2.0/101.0f64;
    let mut exact_close=0usize; let mut exact_ema=0usize; let mut exact_ratio=0usize;
    let mut first_close_bad:Option<String>=None; let mut first_ema_bad:Option<String>=None; let mut first_ratio_bad:Option<String>=None;
    let mut max_close=0.0f64; let mut max_ema=0.0f64; let mut max_ratio=0.0f64;
    for (n,line) in input.lines().enumerate().skip(1) {
        let row:Vec<&str>=line.split('|').collect();
        if row.len()!=14 { eprintln!("bad input row {}: {} fields",n+1,row.len()); process::exit(3); }
        let date=row[0]; let session=row[1];
        let episode=if row[2]=="NULL" || row[2].is_empty() {None} else {Some(row[2].to_owned())};
        let raw=opt(row[4]); let ratio=opt(row[5]); let traded=row[8]=="t" || row[8]=="true";
        if let (Some(ep),Some(_))=(episode.as_ref(),raw) {
            if factor_episode.as_deref()!=Some(ep.as_str()) { cumulative_log=0.0; factor_episode=Some(ep.clone()); }
            let r=ratio.unwrap_or_else(|| {eprintln!("missing adjustment ratio on {date}"); process::exit(4)});
            cumulative_log+=r.ln();
        }
        let rust_close=raw.map(|x| x*(-cumulative_log).exp());
        let reset=prior_episode!=episode;
        if let Some(c)=rust_close {
            if reset { ema=Some(c); count=usize::from(traded); }
            else {
                count+=usize::from(traded);
                if traded { ema=Some(alpha*c+(1.0-alpha)*ema.unwrap_or(c)); }
            }
        }
        let rust_ratio=if traded && count>=100 { rust_close.zip(ema).filter(|(_,e)| *e>0.0).map(|(c,e)| c/e-1.0) } else {None};
        let sql_close=opt(row[6]); let sql_ema=opt(row[11]); let sql_ratio=opt(row[12]); let stored=opt(row[13]);
        let close_err=rel(sql_close,rust_close); let ema_err=rel(sql_ema,ema); let ratio_err=rel(sql_ratio,rust_ratio);
        if sql_close!=rust_close {exact_close+=1;} if sql_ema!=ema {exact_ema+=1;} if sql_ratio!=rust_ratio {exact_ratio+=1;}
        if let Some(e)=close_err {max_close=max_close.max(e); if e>1e-9 && first_close_bad.is_none(){first_close_bad=Some(date.to_owned());}}
        if let Some(e)=ema_err {max_ema=max_ema.max(e); if e>1e-9 && first_ema_bad.is_none(){first_ema_bad=Some(date.to_owned());}}
        if let Some(e)=ratio_err {max_ratio=max_ratio.max(e); if e>1e-9 && first_ratio_bad.is_none(){first_ratio_bad=Some(date.to_owned());}}
        output.push_str(&format!("{date}|{session}|{}|{}|{}|{}|{}|{}|{}|{}|{count}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}\n",
            episode.as_deref().unwrap_or("NULL"),row[3],row[4],row[5],fmt(sql_close),fmt(rust_close),row[9],row[10],fmt(sql_ema),fmt(ema),fmt(sql_ratio),fmt(rust_ratio),fmt(stored),fmt(close_err),fmt(ema_err),fmt(ratio_err),pass(sql_close,rust_close),pass(sql_ema,ema),pass(sql_ratio,rust_ratio)));
        prior_episode=episode;
    }
    fs::write(&a[2],output).unwrap();
    eprintln!("rows={}; exact_differences(close/ema/ratio)={}/{}/{}; max_relative_error={:.17e}/{:.17e}/{:.17e}; first_gt_1e-9(close/ema/ratio)={:?}/{:?}/{:?}",
        input.lines().count().saturating_sub(1),exact_close,exact_ema,exact_ratio,max_close,max_ema,max_ratio,first_close_bad,first_ema_bad,first_ratio_bad);
}