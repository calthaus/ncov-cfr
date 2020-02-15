# Estimating case fatality ratio (CFR) of COVID-19
# Christian L. Althaus, 15 February 2020

# Load libraries
library(lubridate)
library(bbmle)
library(plotrix)

# Estimating gamma distribution of onset of death from Linton et al. (http://dx.doi.org/10.1101/2020.01.26.20018754)
linton <- function(shape, rate) {
    ssr <- sum((qgamma(c(0.05, 0.5, 0.95), shape = exp(shape), rate = exp(rate)) - c(6.1, 14.3, 28.0))^2)
    return(ssr)
}
free_linton <- c(shape = log(4), rate = log(4/14.3))
fit_linton <- mle2(linton, start = as.list(free_linton), method = "Nelder-Mead")

png("figures/ncov_dist.png", height = 250, width = 300)
curve(dgamma(x, exp(coef(fit_linton)[[1]]), exp(coef(fit_linton)[[2]])), 0, 40,
      col = "steelblue", xlab = "Time from onset to death (days)", ylab = "Probability density",
      frame = FALSE)
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
files <- list.files("data", pattern = ".csv")
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
    fixed <- c(death_shape = exp(coef(fit_linton)[[1]]), death_rate = exp(coef(fit_linton)[[2]]))
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
png("figures/ncov_cfr.png", height = 250, width = 300)
plotCI(estimates$date, estimates$mle,
	   ui = estimates$upper, li = estimates$lower,
	   ylim = c(0, 0.2), pch = 16, col = "steelblue",
	   xlab = NA, ylab = "Case fatality ratio", axes = FALSE, frame = FALSE)
axis(1, estimates$date, paste0(day(estimates$date), "/", month(estimates$date)))
axis(2)
dev.off()
