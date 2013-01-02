-- sqlite3 geonames.db < geonames-setup.txt

-- READ THE GEONAMES FILES INTO TABLES

CREATE TEMP TABLE geonames(
  "geonameid" INTEGER
  ,"name" TEXT COLLATE NOCASE
  ,"asciiname" TEXT COLLATE NOCASE
  ,"alternatenames" TEXT
  ,"latitude" REAL 
  ,"longitude" REAL
  ,"feature class" TEXT
  ,"feature code" TEXT
  ,"country code" TEXT
  ,"cc2" TEXT
  ,"admin1 code" TEXT
  ,"admin2 code" TEXT
  ,"admin3 code" TEXT
  ,"admin4 code" TEXT
  ,"population" INTEGER
  ,"elevation" INTEGER
  ,"dem" INTEGER
  ,"timezone" TEXT
  ,"modification date" TEXT
);

.separator "\t"
.import allCountries.txt geonames

CREATE TEMP TABLE altnames(
  alternateNameId INTEGER
  ,geonameid INTEGER
  ,isolanguage TEXT
  ,"alternate name" TEXT
  ,isPreferredName INTEGER
  ,isShortName INTEGER
  ,isColloquial INTEGER
  ,isHistoric INTEGER
);

.separator "\t"
.import alternateNames.txt altnames

-- BUILD A NEW TABLE THAT MATCHES EACH PLACE NAME TO A FULL GEOGRAPHICAL HIERARCHY

CREATE TEMP TABLE geonamesAandP AS
SELECT t1."name"
  ,t1."geonameid"
  ,t1."asciiname"
  ,t1."latitude"
  ,t1."longitude"
  ,t1."feature class"
  ,t1."feature code"
  ,t1."country code"
  ,(CASE WHEN t1."country code"<>'' THEN
     (SELECT t2.geonameid FROM geonames AS t2 WHERE t2."feature code"="PCLI" AND t2."country code" = t1."country code")
   ELSE
     NULL
   END) AS "country geonameid"
  -- note that admin unit codes are only unique within the containing admin unit
  -- the feature code test is because sometimes admin1 is set to 00 when the record concerns a country
  ,(CASE WHEN t1."admin1 code"<>'' AND t1."feature code"<>"PCLI" THEN
     (SELECT t2.geonameid
      FROM geonames AS t2 
      WHERE t2."country code" = t1."country code"
        AND t2."feature code"="ADM1"
        AND t2."admin1 code" = t1."admin1 code")
   ELSE
     NULL
   END) AS "admin1 geonameid"
  ,(CASE WHEN t1."admin2 code"<>'' THEN
     (SELECT t2.geonameid 
      FROM geonames AS t2 
      WHERE t2."country code" = t1."country code" 
        AND t2."admin1 code" = t1."admin1 code"
        AND t2."feature code"="ADM2" 
        AND t2."admin2 code" = t1."admin2 code")
   ELSE
     NULL
   END) AS "admin2 geonameid"
  ,(CASE WHEN t1."admin3 code"<>'' THEN
     (SELECT t2.geonameid
        FROM geonames AS t2 
        WHERE t2."country code" = t1."country code" 
          AND t2."admin1 code" = t1."admin1 code"
          AND t2."admin2 code" = t1."admin2 code"
          AND t2."feature code"="ADM3" 
          AND t2."admin3 code" = t1."admin3 code")
   ELSE
     NULL
   END) AS "admin3 geonameid"
  ,(CASE WHEN t1."admin4 code"<>'' THEN
     (SELECT t2.geonameid 
      FROM geonames AS t2 
      WHERE t2."country code" = t1."country code"
        AND t2."admin1 code" = t1."admin1 code"
        AND t2."admin2 code" = t1."admin2 code"
        AND t2."admin3 code" = t1."admin3 code"
        AND t2."feature code"="ADM4" 
        AND t2."admin4 code" = t1."admin4 code")
   ELSE
     NULL
   END) AS "admin4 geonameid"
FROM geonames AS t1  
WHERE t1."feature class"='A' OR t1."feature class"='P';

CREATE TEMP TABLE altnamesWithHierarchy AS
SELECT altnames."alternate name" AS name
  ,altnames.geonameid
  ,geonamesAandP.latitude
  ,geonamesAandP.longitude
  ,geonamesAandP."feature class"
  ,geonamesAandP."feature code"
  ,geonamesAandP."country code"
  ,geonamesAandP."country geonameid"
  ,geonamesAandP."admin1 geonameid"
  ,geonamesAandP."admin2 geonameid"
  ,geonamesAandP."admin3 geonameid"
  ,geonamesAandP."admin4 geonameid"
FROM altnames, geonamesAandP 
WHERE altnames.isolanguage!='link' AND altnames.geonameid = geonamesAandP.geonameid;

CREATE TABLE geonamesAll AS
SELECT "name"
  ,"geonameid"
  ,"latitude"
  ,"longitude"
  ,"feature class"
  ,"feature code"
  ,"country code"
  ,"country geonameid"
  ,"admin1 geonameid"
  ,"admin2 geonameid"
  ,"admin3 geonameid"
  ,"admin4 geonameid" 
FROM geonamesAandP
UNION
SELECT "asciiname" AS "name"
  ,"geonameid"
  ,"latitude"
  ,"longitude"
  ,"feature class"
  ,"feature code"
  ,"country code"
  ,"country geonameid"
  ,"admin1 geonameid"
  ,"admin2 geonameid"
  ,"admin3 geonameid"
  ,"admin4 geonameid" 
FROM geonamesAandP
UNION
SELECT "country code" AS "name"
  ,"geonameid"
  ,"latitude"
  ,"longitude"
  ,"feature class"
  ,"feature code"
  ,"country code"
  ,"country geonameid"
  ,"admin1 geonameid"
  ,"admin2 geonameid"
  ,"admin3 geonameid"
  ,"admin4 geonameid" 
FROM geonamesAandP
WHERE "feature code"='PCLI'
UNION
SELECT * FROM altnamesWithHierarchy;

-- BUILD A TABLE THAT MATCHES EACH GEONAMEID TO A 'CANONICAL' PLACE NAME

-- The canonical place name is, somewhat arbitrarily, set to be what is recorded to be the place name's short form in English.
-- It must be possible to do all of this with some kind of join, no?

CREATE TEMP TABLE t1 AS
SELECT geonamesAandP.geonameid, altnames."alternate name" AS name
FROM geonamesAandP, altnames
WHERE geonamesAandP.geonameid=altnames.geonameid AND altnames.isShortName=1 AND altnames.isolanguage='en';

CREATE TEMP TABLE t2 AS
SELECT geonamesAandP.geonameid, altnames."alternate name" AS name
FROM geonamesAandP, altnames
WHERE geonamesAandP.geonameid=altnames.geonameid AND altnames.isShortName=1 AND altnames.isolanguage='' 
AND geonamesAandP.geonameid NOT IN (select t1.geonameid FROM t1);

CREATE TABLE canonicalGeonames AS 
SELECT * FROM t1
UNION
SELECT * FROM t2
UNION
SELECT geonamesAandP.geonameid, geonamesAandP.name AS name
FROM geonamesAandP
WHERE geonamesAandP.geonameid NOT IN (SELECT t1.geonameid FROM t1 UNION SELECT t2.geonameid FROM t2);

-- There are about thirty instances in which two names for the same geonameid satisfy all of the conditions for being 'canonical'
DELETE FROM canonicalGeonames WHERE rowid NOT IN (SELECT MAX(rowid) FROM canonicalGeonames GROUP BY geonameid);

CREATE INDEX canonicalGeonamesIdIndex ON canonicalGeonames (geonameid);

CREATE INDEX geonamesAllNameIndex ON geonamesAll (name COLLATE NOCASE);


