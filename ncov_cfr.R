# Estimating case fatality ratio (CFR) of 2019-nCoV
# Christian L. Althaus, 8 February 2020

# Load libraries
library(lubridate)
library(bbmle)
library(plotrix)

# Load 2019-nCoV cases (n=130) identified outside of China 
# Source: WHO Novel Coronavirus(2019-nCoV) Situation Report - 19, and media reports for the death on the Philippines
exports <- read.csv("data/ncov_cases_20200208.csv")
begin <- ymd(exports$date[1])
cases <- exports$cases
deaths <- exports$deaths
n_cases <- sum(cases)
n_deaths <- sum(deaths)
n_days <- length(cases)
days <- 1:n_days
interval <- seq(1, n_days + 7, 7)
onset <- rep(days, cases)

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
	ll <- sum(dpois(deaths, expected, log = TRUE)) # Daily incidence of deaths
	#ll <- dpois(1, sum(expected), log = TRUE) # Cumulative incidence of deaths
	return(-ll)
}

mortality <- function(cfr, death_shape, death_rate) {
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
	return(expected)
}

# Fit the model
free <- c(cfr = 0)
fixed <- c(death_shape = exp(coef(fit_linton)[[1]]), death_rate = exp(coef(fit_linton)[[2]]))
fit <- mle2(nll, start = as.list(free), fixed = as.list(fixed), method = "Brent", lower = -100, upper = 100)
summary(fit)
plogis(coef(fit)[1])
confidence <- confint(fit)
plogis(confidence)

# Plot the data
png("figures/ncov_cases.png", height = 250, width = 600)
par(mfrow = c(1, 2))
barplot(cases,
		col = "steelblue", xlab = "Data: WHO Situation Report 19", ylab = "Cases",
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

# Plot the estimtate and future changes
png("figures/ncov_cfr.png", height = 250, width = 300)
x_date <- c(ymd(20200202), ymd(20200203), ymd(20200204), ymd(20200205), ymd(20200206), ymd(20200207), ymd(20200208))
y_estimate <- c(0.04271349, 0.04129256, 0.03936208, 0.02604126, 0.01990869, 0.01712611, 0.01510122)
y_upper <- c(0.187970288, 0.181715697, 0.173219590, 0.114629818, 0.087621213, 0.0753654141, 0.0664487614)
y_lower <- c(0.002435814, 0.002354727, 0.002244574, 0.001484787, 0.001135114, 0.0009764659, 0.0008610193)
plotCI(x_date, y_estimate,
	   ui = y_upper, li = y_lower,
	   xlim = range(x_date), ylim = c(0, 0.2),
	   pch = 16, col = "steelblue",
	   xlab = NA, ylab = "Case fatality ratio", axes = FALSE, frame = FALSE)
axis(1, x_date, wday(x_date, label = TRUE))
axis(2, seq(0, 0.2, 0.05), seq(0, 0.2, 0.05))
dev.off()
