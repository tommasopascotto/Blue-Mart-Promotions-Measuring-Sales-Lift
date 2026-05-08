clear all
set more off

cd "C:\Users\Tomma\OneDrive\Desktop\Personali\past courses\Marketing Analytics\GP\Final Codes"

import delimited using "30420_Project2_data_Group1_sales.csv", ///
    varnames(1) case(lower) clear

* convert to daily date
gen date_stata = daily(date, "YMD")
format date_stata %td
drop date
rename date_stata date

* Promo dummy at row level:
* 1 if the discount is > 0 and not missing
gen byte promo_line = (discount_pct > 0 & discount_pct < .)
label var promo_line "1 se questa transazione ha qualche sconto attivo"

* COLLAPSE at DAY level:
collapse (sum) qty_total = quantity ///
         (max) promo_active = promo_line, ///
         by(date)
		 
label var qty_total "Total quantity sold per day"
label var promo_active "1 if any promo was active that day" 

*CALENDAR VARIABLES (SEASONAL CONTROLS)

gen year  = year(date)
gen month = month(date)

gen byte dow = dow(date)
replace dow = 1 if inlist(dow, 1, 2, 3, 4, 5)
replace dow = 0 if inlist(dow, 0, 6)

label define dowlbl 0 "Weekend" 1 "Weekday"
label values dow dowlbl

* Save base dataset
save "df_manipulated.dta", replace
export delimited using "df_manipulated.csv", replace

* 5. MODEL 1
gen log_qty = log(qty_total)
label var log_qty "log(qty_total)"

reg log_qty i.promo_active i.dow i.month
est store m_log

* Expected effects with and without promo (back-transform to level)
margins promo_active, expression(exp(predict()))

* 6. CONSTRUCTION OF DYNAMIC DATASET (PHASES 5 DAYS PRE/POST)

use "df_manipulated.dta", clear
sort date

* Find the first and last date with promo active
egen promo_start_tmp = min(date) if promo_active == 1
egen promo_end_tmp   = max(date) if promo_active == 1

egen promo_start = min(promo_start_tmp)
egen promo_end   = max(promo_end_tmp)

drop promo_start_tmp promo_end_tmp

* Quick check (optional)
display "Promo start: " %td promo_start
display "Promo end:   " %td promo_end

* Define phase:
* 1 = baseline (default)
* 3 = promo
* 4 = post (up to 5 days after promo end)

gen byte phase = .
replace phase = 3 if promo_active == 1
replace phase = 4 if promo_active == 0 & date >  promo_end   & date <= promo_end + 5
replace phase = 1 if missing(phase)

label define phase_lbl 1 "baseline" 2 "pre" 3 "promo" 4 "post"
label values phase phase_lbl
label var phase "Dynamic promo phase (5d pre/post)"

save "new_dataset_dynamic_effects_5d.dta", replace
export delimited using "new_dataset_dynamic_effects_5d.csv", replace

* 7. MODEL 2: LOG WITH DYNAMIC PHASES

use "new_dataset_dynamic_effects_5d.dta", clear

gen log_qty = log(qty_total)
label var log_qty "log(qty_total)"

reg log_qty i.phase i.dow i.month
est store m_log_phase

* Predictions for each phase (back-transformed)
margins phase, expression(exp(predict()))
