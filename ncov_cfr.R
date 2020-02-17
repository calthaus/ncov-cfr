# Estimating case fatality ratio (CFR) of COVID-19
# Christian L. Althaus, 16 February 2020

# Load libraries
library(lubridate)
library(bbmle)
library(plotrix)
library(fitdistrplus)

# Estimating distribution from onset of symptoms to death
# Linton et al. (https://doi.org/10.3390/jcm9020538)
linton <- read.csv("data/linton_supp_tableS1_S2_8Feb2020.csv")
linton <- dmy(linton$Death) - dmy(linton$Onset)
linton <- as.numeric(na.omit(linton))
fit_linton <- fitdist(linton, "gamma")

# Imperial College London (https://www.imperial.ac.uk/media/imperial-college/medicine/sph/ide/gida-fellowships/Imperial-College-2019-nCoV-severity-10-02-2020.pdf)
imperial <- read.csv("data/hubei_early_deaths_2020_07_02.csv")
imperial <- dmy(imperial$date_death) - dmy(imperial$date_onset)
imperial <- as.numeric(na.omit(imperial))
fit_imperial <- fitdist(imperial, "gamma")

png("figures/ncov_dist.png", height = 250, width = 300)
curve(dgamma(x, coef(fit_linton)[[1]], coef(fit_linton)[[2]]), 0, 40,
      col = "steelblue", xlab = "Time from onset to death (days)", ylab = "Probability density",
      frame = FALSE)
linton_mean <- coef(fit_linton)[[1]]/coef(fit_linton)[[2]]
linton_median <- qgamma(0.5, coef(fit_linton)[[1]], coef(fit_linton)[[2]])
lines(c(linton_mean, linton_mean), c(0, dgamma(linton_mean, coef(fit_linton)[[1]], coef(fit_linton)[[2]])), col = "steelblue", lty = 2)
lines(c(linton_median, linton_median), c(0, dgamma(linton_median, coef(fit_linton)[[1]], coef(fit_linton)[[2]])), col = "steelblue", lty = 3)
dev.off()

# Likelihood and expected mortality function
nll <- function(cfr, death_shape, death_rate) {
    cfr <- plogis(cfr)
    expected <- numeric(n_days)
    for(i in days) {
        for(j in 1:n_cases) {
            d <- i - onset[j]
            if(d >= 0) {
                expected[i] <- expected[i] + cfr*diff(pgamma(c(d - 0.5, d + 0.5), shape = death_shape, rate = death_rate))
            }
        }
    }
    ll <- sum(dpois(deaths, expected, log = TRUE))
    return(-ll)
}

# Analyze all data sets of observed COVID-19 cases outside China
# Source: WHO, ECDC and international media
files <- list.files("data", pattern = "ncov_cases")
estimates <- as.data.frame(matrix(NA, nrow = length(files), ncol = 4))
names(estimates) <- c("date", "mle", "lower", "upper")
for(i in 1:length(files)) {
    # Prepare data
    file_date <- ymd(substr(files[i], 12, 19))
    exports <- read.csv(paste0("data/", files[i]))
    begin <- ymd(exports$date[1])
    cases <- exports$cases
    deaths <- exports$deaths
    n_cases <- sum(cases)
    n_deaths <- sum(deaths)
    n_days <- length(cases)
    days <- 1:n_days
    interval <- seq(1, n_days + 7, 7)
    onset <- rep(days, cases)
    
    # Fit the model
    free <- c(cfr = 0)
    fixed <- c(death_shape = coef(fit_linton)[[1]], death_rate = coef(fit_linton)[[2]])
    fit <- mle2(nll, start = as.list(free), fixed = as.list(fixed), method = "Brent", lower = -100, upper = 100)
    
    # Write estimates
    estimates[i, 1] <- as_date(file_date)
    estimates[i, 2] <- plogis(coef(fit)[1])
    estimates[i, 3:4] <- plogis(confint(fit))
}

# Save estimates
estimates$date <- as_date(estimates$date)
saveRDS(estimates, "out/cfr.rds")

# Plot the most recent data set
png("figures/ncov_cases.png", height = 250, width = 600)
par(mfrow = c(1, 2))
barplot(cases,
		col = "steelblue", xlab = "Data: WHO Situation Reports", ylab = "Cases",
		main = "Symptom onset in cases outside China", axes = FALSE, frame = FALSE)
axis(1, interval, begin + interval - 1)
axis(2)
barplot(deaths,
		ylim = c(0, max(cases)),
		col = "tomato", xlab = "Data: WHO, ECDC, Media", ylab = "Deaths",
		main = "Deaths among cases outside China", axes = FALSE, frame = FALSE)
axis(1, interval, begin + interval - 1)
axis(2)
dev.off()

# Plot the estimates
png("figures/ncov_cfr.png", height = 250, width = 600)
plotCI(estimates$date, estimates$mle,
	   ui = estimates$upper, li = estimates$lower,
	   ylim = c(0, 0.2), pch = 16, col = "steelblue",
	   xlab = NA, ylab = "Case fatality ratio", axes = FALSE, frame = FALSE)
axis(1, estimates$date, paste0(day(estimates$date), "/", month(estimates$date)))
axis(2)
dev.off()
