import Foundation

/// Real HTML/JSON samples captured from the live
/// `cotralspa.it/wp-json/cotral/v1/get-train-stopsroute` endpoint (a
/// Metromare query, `RL_CC-PSP`), trimmed to a couple of stations/passages
/// each for readability — not synthesized, so a test against these is a
/// test against what the site actually sends, not against an assumption of
/// what it should send. See `CotralTrainScheduleParserTests`.
enum TrainScheduleFixtures {
    /// The widget HTML alone (already unwrapped), 2 stations: "Cristoforo
    /// Colombo" (4 passages) and "Castelfusano" (3 passages), all "In
    /// orario". Trimmed from a real ~200KB response (14 stations, 462
    /// passages) captured 2026-09-18.
    static let twoStationsHTML = #"""
    <div class="TrainsRealtimeStops">
    <div class="TrainsRealtimeStops__wrapper flex flex-col">
    <div class="LocalityAccordion --realtime --inline"
    	data-tw-controller="locality-accordion">
    	<div class="LocalityAccordion__main-wrapper relative bg-neutral-white w-full h-full" data-section-download=section-download-6aad11d421147>
    		<button class="LocalityAccordion__button w-full flex flex-col lg:flex-row justify-between lg:justify-start" id="trigger-6aad11d421146"
    		role="button" aria-expanded="false" aria-controls="panel-6aad11d421146">		<span class="LocalityAccordion__button-content-left">
    								<span class="LocalityAccordion__text-wrapper flex-col">
    					<span class="LocalityAccordion__text heading-h3 text-primary-blue-dark">
    						<span>
    							Cristoforo Colombo						</span>
    					</span>
    				</span>
    					</span>
    		<span class="LocalityAccordion__button-content-right">
    											<span class="LocalityAccordion__open-text text-primary-blue-light text-button font-filson-pro uppercase"
    							data-html2canvas-ignore
    							data-open-text=""
    							data-close-text="">
    											</span>
    					<span class="LocalityAccordion__open-icon">
    						<svg class="LocalityAccordion__open-svg --closed">
    							<use xlink:href="#icon-plus"></use>
    						</svg>
    						<svg class="LocalityAccordion__open-svg --opened">
    							<use xlink:href="#icon-minus"></use>
    						</svg>
    					</span>
    						</span>
    		</button>			<div class="LocalityAccordion__content-wrapper"
    					 id="panel-6aad11d421146"
    					 role="region"
    					 aria-labelledby="trigger-6aad11d421146">
    				<span class="LocalityAccordion__loader">
    					<svg class="LocalityAccordion__loader-svg">
    						<use xlink:href="#icon-loader"></use>
    					</svg>
    				</span>
    				<div class="LocalityAccordion__content">

    <div class="TimeTable flex flex-col gap-50 lg:gap-40">
    	<div class="TimeTable__cards flex flex-row flex-wrap justify-center gap-x-12 md:gap-x-16 gap-y-20 lg:gap-y-24 lg:justify-start">

    <div class="TimeCard flex flex-col justify-center border rounded-[0.8rem] --time --realtime">
    	<div class="TimeCard__time-wrapper rounded-[0.8rem] p-18 flex flex-col justify-center items-center gap-6 w-full">
    		<span class="TimeCard__time text-ttl-18 text-primary-blue-dark font-filson-pro font-bold">
    			11:40		</span>
    	</div>

    	<div class="TimeCard__info text-center font-bold py-10 ">
    		In orario	</div>

    </div>
    <div class="TimeCard flex flex-col justify-center border rounded-[0.8rem] --time --realtime">
    	<div class="TimeCard__time-wrapper rounded-[0.8rem] p-18 flex flex-col justify-center items-center gap-6 w-full">
    		<span class="TimeCard__time text-ttl-18 text-primary-blue-dark font-filson-pro font-bold">
    			12:00		</span>
    	</div>

    	<div class="TimeCard__info text-center font-bold py-10 ">
    		In orario	</div>

    </div>
    <div class="TimeCard flex flex-col justify-center border rounded-[0.8rem] --time --realtime">
    	<div class="TimeCard__time-wrapper rounded-[0.8rem] p-18 flex flex-col justify-center items-center gap-6 w-full">
    		<span class="TimeCard__time text-ttl-18 text-primary-blue-dark font-filson-pro font-bold">
    			12:20		</span>
    	</div>

    	<div class="TimeCard__info text-center font-bold py-10 ">
    		In orario	</div>

    </div>
    <div class="TimeCard flex flex-col justify-center border rounded-[0.8rem] --time --realtime">
    	<div class="TimeCard__time-wrapper rounded-[0.8rem] p-18 flex flex-col justify-center items-center gap-6 w-full">
    		<span class="TimeCard__time text-ttl-18 text-primary-blue-dark font-filson-pro font-bold">
    			12:40		</span>
    	</div>

    	<div class="TimeCard__info text-center font-bold py-10 ">
    		In orario	</div>

    </div>
    </div>	</div>

    	</div>

    				</div>
    			</div>
    				</div>
    </div>
    <div class="LocalityAccordion --realtime --inline"
    	data-tw-controller="locality-accordion">
    	<div class="LocalityAccordion__main-wrapper relative bg-neutral-white w-full h-full" data-section-download=section-download-6aad11d45379e>
    		<button class="LocalityAccordion__button w-full flex flex-col lg:flex-row justify-between lg:justify-start" id="trigger-6aad11d45379d"
    		role="button" aria-expanded="false" aria-controls="panel-6aad11d45379d">		<span class="LocalityAccordion__button-content-left">
    								<span class="LocalityAccordion__text-wrapper flex-col">
    					<span class="LocalityAccordion__text heading-h3 text-primary-blue-dark">
    						<span>
    							Castelfusano						</span>
    					</span>
    				</span>
    					</span>
    		<span class="LocalityAccordion__button-content-right">
    											<span class="LocalityAccordion__open-text text-primary-blue-light text-button font-filson-pro uppercase"
    							data-html2canvas-ignore
    							data-open-text=""
    							data-close-text="">
    											</span>
    					<span class="LocalityAccordion__open-icon">
    						<svg class="LocalityAccordion__open-svg --closed">
    							<use xlink:href="#icon-plus"></use>
    						</svg>
    						<svg class="LocalityAccordion__open-svg --opened">
    							<use xlink:href="#icon-minus"></use>
    						</svg>
    					</span>
    						</span>
    		</button>			<div class="LocalityAccordion__content-wrapper"
    					 id="panel-6aad11d45379d"
    					 role="region"
    					 aria-labelledby="trigger-6aad11d45379d">
    				<span class="LocalityAccordion__loader">
    					<svg class="LocalityAccordion__loader-svg">
    						<use xlink:href="#icon-loader"></use>
    					</svg>
    				</span>
    				<div class="LocalityAccordion__content">

    <div class="TimeTable flex flex-col gap-50 lg:gap-40">
    	<div class="TimeTable__cards flex flex-row flex-wrap justify-center gap-x-12 md:gap-x-16 gap-y-20 lg:gap-y-24 lg:justify-start">

    <div class="TimeCard flex flex-col justify-center border rounded-[0.8rem] --time --realtime">
    	<div class="TimeCard__time-wrapper rounded-[0.8rem] p-18 flex flex-col justify-center items-center gap-6 w-full">
    		<span class="TimeCard__time text-ttl-18 text-primary-blue-dark font-filson-pro font-bold">
    			11:42		</span>
    	</div>

    	<div class="TimeCard__info text-center font-bold py-10 ">
    		In orario	</div>

    </div>
    <div class="TimeCard flex flex-col justify-center border rounded-[0.8rem] --time --realtime">
    	<div class="TimeCard__time-wrapper rounded-[0.8rem] p-18 flex flex-col justify-center items-center gap-6 w-full">
    		<span class="TimeCard__time text-ttl-18 text-primary-blue-dark font-filson-pro font-bold">
    			12:02		</span>
    	</div>

    	<div class="TimeCard__info text-center font-bold py-10 ">
    		In orario	</div>

    </div>
    <div class="TimeCard flex flex-col justify-center border rounded-[0.8rem] --time --realtime">
    	<div class="TimeCard__time-wrapper rounded-[0.8rem] p-18 flex flex-col justify-center items-center gap-6 w-full">
    		<span class="TimeCard__time text-ttl-18 text-primary-blue-dark font-filson-pro font-bold">
    			12:22		</span>
    	</div>

    	<div class="TimeCard__info text-center font-bold py-10 ">
    		In orario	</div>

    </div>
    </div>	</div>

    	</div>

    				</div>
    			</div>
    				</div>
    </div>

    </div></div>
    """#

    /// Well-formed JSON envelope wrapping `twoStationsHTML` (properly
    /// escaped) — the common case.
    static let wellFormedEnvelope: String = {
        let escaped = twoStationsHTML
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return #"{"status":200,"response":"\#(escaped)"}"#
    }()

    /// Same envelope shape, but with the "response" string containing
    /// literal unescaped control characters instead of `\n`/`\t` — breaks
    /// a strict JSON parser (`JSONDecoder` throws on this) even though the
    /// `{"status":...,"response":"..."}` shape is otherwise intact. This
    /// exact malformation was observed from the live endpoint during
    /// testing (not a hypothetical edge case).
    static let malformedControlCharacterEnvelope: String = {
        let escaped = twoStationsHTML
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "{\"status\":200,\"response\":\"\(escaped)\"}"
    }()

    /// The endpoint's actual empty-result shape (an invalid `codicePercorso`
    /// or a missing/malformed `date` both come back this way in practice —
    /// still HTTP 200, just no station accordions inside the wrapper).
    static let emptyEnvelope = #"{"status":200,"response":"\n<div class=\"TrainsRealtimeStops\">\n\t<div class=\"TrainsRealtimeStops__wrapper flex flex-col\">\n\n\t\t\n\t\t\t<\/div>\n<\/div>\n\n"}"#
}
