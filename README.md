#geonames-geocoder.rkt

##Overview

This is a geocoder that uses the Geonames database. It is *not* a wrapper around the Geonames geocoding API. It is a geocoder that runs on one's own computer using a downloaded and restructured Geonames database. It codes freeform addresses and descriptions into administrative hierarchies. It does not, however, resolve populated places within administrative units, deal with postal codes, locate street addresses, or provide reverse geocoding. 

##Installing

As well as Racket, this requires (1) sqlite and (2) two of the Geonames database files.

1. If sqlite is not already installed, it can be obtained at <www.sqlite.org/download.html>.

2. Go to <http://download.geonames.org/export/dump/> and download allCountries.zip and alternateNames.zip.

3. Uncompress these files, and place allCountries.txt and alternateNames.txt in a sub-directory named "Database" within the directory holding geocoder.rkt. (You may well want to lay things out differently; just change the path given in the line `(define gdb (sqlite3-connect #:database "Database/geonames.db" #:mode 'read-only))`

4. Go to `/geonames-geocoder/Database/` and run `sqlite3 geonames.db < ../geonames-setup.sql`. This may take 10-15 minutes, as the structure of the data is being changed significantly to allow faster geocoding.

5. The module should now work.

##Usage

The `geocode` function codes freeform addresses and descriptions into administrative hierarchies. For example:

	(geocode "Pulluvila P.O., Trivandrum")
	==> '((ADM0 1269750 "Republic of India") (ADM1 1267254 "Kerala") (ADM2 1254164 "Trivandrum"))

	(geocode "123 Empire Ave, Apt A3, Far Rockaway, NY")
	==> '((ADM0 6252001 "United States") (ADM1 5128638 "New York") (ADM2 5133268 "Queens"))

	(geocode "Санкт-Петербург Россия")
	==> '((ADM0 2017370 "Russia") (ADM1 536203 "St.-Petersburg"))

If `geocode` fails to locate the given place names, it will return the empty list.

`geocode` also has four optional arguments:

* #:left-to-right? - defaults to #f because, in most countries, addresses and the like are given with the major admin units last

* #:label? - defaults to #t; annotates geonameids with place names (as seen above), which is helpful but which also requires additional database queries

* #:short-circuit? - defaults to #t, meaning that the function will return (without looking at the rest of the string) as soon as it is able to return a consistent hierarchy with requested number of levels sought. 

* #:level-sought - defaults to 2 and signifies how deep of a geographical hierarchy should be obtained before short-circuiting. This can range from 0 (country) to 5 (small subnational unit). In the US, states are level 1, and counties are level 2. Not all countries have administrative units at all of these levels. Note that setting level-sought to, say, 2 does not guarantee that the returned hierarchy will only be two levels deep: If the query term that permitted level 2 to be resolved also allowed level 3 to be resolved, that will be returned too. Note also that, the higher the level sought is set, the more likely that the geocoder will find it impossible to establish a hierarchy consistent with all of the query results and thus return the empty list. (This should certainly not be considered a feature, but user beware.)

The `query-geoname` and `query-geoname-with-feature-code` return somewhat more raw results.

	(query-geoname "Dubai")
	==>'(#(292223 25.25817 55.30472 "P" "PPLA" "AE" 290557 292224 #<sql-null> #<sql-null> #<sql-null>)
	     #(292224 25.0 55.33333 "A" "ADM1" "AE" 290557 292224 #<sql-null> #<sql-null> #<sql-null>)
	     #(1272695 27.64324 78.28848 "P" "PPL" "IN" 1269750 1253626 #<sql-null> #<sql-null> #<sql-null>)
	     #(6861395 31.681 106.90118 "P" "PPL" "CN" 1814991 1794299 #<sql-null> #<sql-null> #<sql-null>))

	(query-geoname-with-feature-code "Dubai" "PPL")
	==>'(#(1272695 27.64324 78.28848 "P" "PPL" "IN" 1269750 1253626 #<sql-null> #<sql-null> #<sql-null>)
	     #(6861395 31.681 106.90118 "P" "PPL" "CN" 1814991 1794299 #<sql-null> #<sql-null> #<sql-null>))

The feature codes are simply those defined in Geonames and are listed at <http://www.geonames.org/export/codes.html>.

There are also two simple utilities - `geonameid->name` and `geonameid->lat/long` - that do what their names suggest:

	(geonameid->name 292224)
	==>"Dubai"

	(geonameid->lat/long 292224)
	==>'#(25.0 55.33333)

##How it works

When working on a geocoder, you quickly realize that there are many possible approaches, all flawed. When using a geocoder, it is important, then, to know the approach being taken so as to see where the traps are hidden. 

The `geocode` function takes a fairly naive approach to geocoding, which has both advantages and disadvantages. On the advantages side of the ledger, it can geocode addresses and other location information in any language (insofar as the names are in the Geonames 
database) and does not get tripped up by typical data imperfections, such as giving a district capital's name in a district name
field. On the disadvantages side of the ledger, it ignores the useful information that is provided by the formats of addresses and
location tables, resulting in some errors and failed attempts.

It moves through the string from right to left (by default), first tokenizing using commas as separators and, if a given token cannot be found in the database, then further tokenizing on spaces and punctuation. On each token, it is simply running `query-geoname`. As it does so, it attempts to reconcile each new set of results with those produced by earlier tokens.

Take the example of what happens when `(geocode "321 Main Street, Omaha, Nebraska")` is evaluated:

First, "Nebraska" is coded:

	(query-geoname "Nebraska")
	==>'(#(4262005 39.06366 -85.45941 "P" "PPL" "US" 6252001 4921868 4259679 #<sql-null> #<sql-null>)
	     #(4481577 35.45767 -76.06324 "P" "PPL" "US" 6252001 4482348 4472505 #<sql-null> #<sql-null>)
	     #(5073708 41.50028 -99.75067 "A" "ADM1" "US" 6252001 5073708 #<sql-null> #<sql-null> #<sql-null>)
	     #(5202949 41.46923 -79.38338 "P" "PPL" "US" 6252001 6254927 5189967 #<sql-null> #<sql-null>)
	     #(5202950 41.52425 -75.53713 "P" "PPL" "US" 6252001 6254927 5196674 #<sql-null> #<sql-null>))

Second, "Omaha" is coded.

	(query-geoname "Omaha")
	==>'(#(4081619 33.30262 -85.31023 "P" "PPL" "US" 6252001 4829764 4085418 #<sql-null> #<sql-null>)
	     #(4124911 36.45229 -93.18851 "P" "PPL" "US" 6252001 4099753 4102608 #<sql-null> #<sql-null>)
	     #(4214292 32.14626 -85.01326 "P" "PPL" "US" 6252001 4197000 4224592 #<sql-null> #<sql-null>)
	     #(4246389 37.89032 -88.3031 "P" "PPL" "US" 6252001 4896861 4239230 #<sql-null> #<sql-null>)
	     #(4303219 37.2751 -82.84183 "P" "PPL" "US" 6252001 6254925 4297180 #<sql-null> #<sql-null>)
	     #(4716696 33.18068 -94.7441 "P" "PPL" "US" 6252001 4736286 4712390 #<sql-null> #<sql-null>)
	     #(4777398 37.09761 -82.43459 "P" "PPL" "US" 6252001 6254928 4755865 #<sql-null> #<sql-null>)
	     #(5056660 40.53252 -92.80075 "P" "PPL" "US" 6252001 4398678 5056963 #<sql-null> #<sql-null>)
	     #(5074472 41.25861 -95.93779 "P" "PPLA2" "US" 6252001 5073708 5067114 #<sql-null> #<sql-null>)) 

Third, the two sets of results are reconciled, resulting in a list of all locations taken from the first set of results that could refer (at another geographical level) to any location taken from the second set of results.

	(reconcile-queries (query-geoname "Omaha") (query-geoname "Nebraska"))
	==>'(#(5074472 41.25861 -95.93779 "P" "PPLA2" "US" 6252001 5073708 5067114 #<sql-null> #<sql-null>))
	'(#(5073708 41.50028 -99.75067 "A" "ADM1" "US" 6252001 5073708 #<sql-null> #<sql-null> #<sql-null>))

Fourth, the geocoder identifies the deepest geographical hierarchy that is consistent with all of the results after reconciliation. 

	(lcd (reconcile-query-with-query-set (query-geoname "Omaha") (list (query-geoname "Nebraska"))))
	==>'(6252001 5073708 5067114)

	(label-hierarchy '(6252001 5073708 5067114))
	==>'((ADM0 6252001 "United States") (ADM1 5073708 "Nebraska") (ADM2 5067114 "Douglas County"))

As the `level-sought` option for `geocode` was set to its default of 2, this result is returned before the geocoder has ever looked at the rest of the string.

The difference between this fourth step and the earlier reconciliation would be more obvious if there was a second city or other place in Nebraska named Omaha. In that case the inconsistency regarding the county would have resulted in `'((ADM0 6252001 "United States") (ADM1 5073708 "Nebraska"))` being returned.

##Issues and extensions

* Because the geocoder insists that the final returned result be consistent with some result provided for every query term, the more of the string that is coded, the more likely that it will encounter a (spurious) contradiction - note that there are places named both "Main" and "Street", and those places are not located in Nebraska. This is partly a fairly fundamental limitation of the approach but there is no reason to have:

	(geocode "321 Main Street, Omaha, Nebraska" #:level-sought 2)
	==>'((ADM0 6252001 "United States") (ADM1 5073708 "Nebraska") (ADM2 5067114 "Douglas County"))

	(geocode "321 Main Street, Omaha, Nebraska" #:level-sought 4)
	==>'()

* Another splitter should be added, so that it is first commas, then spaces and puntuation other than hyphens, and finally hyphens. This would prevent this absurdity:

	(geocode ", Санкт-Петербург 190000 Россия")
	==>'((ADM0 2017370 "Russia"))
	(geocode "Санкт-Петербург 190000 Россия")
	==>'((ADM0 2017370 "Russia") (ADM1 536203 "St.-Petersburg"))

This is trivial, but it is a bit of a pain because Racket's regular expression parser does not handle substractions between Unicode character categories.

* Should take advantage of the Geonames postal code files.

* There would be major performance gains if one added a column to the geonamesAll table based on the kinds of characters that appear in the name (ascii/latin/cyrillic/etc.), indexed that column, and then limited queries after inspecting the string. 

* Should geocode down to the populated places level. To do this sensibly, one would also need to use the Geonames hierarchy file - which contains hierarchies among populated places (additional to the administrative hierarchies already contained in the allCountries file).
