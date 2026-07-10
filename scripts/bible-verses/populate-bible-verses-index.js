import fs from 'fs';
import algoliasearch from 'algoliasearch';
import fetch from 'isomorphic-fetch';
import queryString from 'query-string';

import { addRecordToIndex } from '../helpers/index';

const client = algoliasearch(process.env.ALGOLIA_API_KEY, process.env.ALGOLIA_SECRET_KEY);

const bibleIndex = client.initIndex('bible verses');
const readFrom = '../normalized-data/deduped-bible-verses.json';

const cache = {};

const esvFetchInterval = 5000;
const { ESV_API_SECRET } = process.env;
// const SCRIPTURE_API_SECRET = process.env.SCRIPTURE_API_SECRET;
let start = Date.now();
// const lastCitationSaved = 'Matt.5.25';

const logTime = (end) => {
  const elapsed = end - start;
  console.log('TIME SINCE LAST INVOCATION: ---- **********', Math.floor(elapsed / 1000));
  start = Date.now();
};

// API REQUEST:
// const baseUrl = 'https://api.scripture.api.bible/v1/bibles/06125adad2d5898a-01/passages';
const baseUrl = 'https://api.esv.org/v3/passage/text';

const getQueryParams = (bibleText) => queryString.stringify({
  q: bibleText,
  'content-type': 'json',
  'include-passage-references': false,
  'include-footnotes': false,
  'include-footnote-body': false,
  'include-headings': false,
});

const areWeThrottled = (resp) => {
  if (Object.keys(resp).includes('detail')) {
    if (resp.detail.includes('throttled')) {
      return true;
    }
  }
  return false;
};

const getBibleVerse = (bibleText, { citedBy }) => {
  if (Object.keys(cache).includes(bibleText)) {
    console.info('CACHE HIT', bibleText);
    return Promise.resolve({
      bibleText: cache.bibleText,
      citedBy,
      // confession,
    });
  }
  if (!bibleText) return Promise.resolve({ bibleText: '', citedBy });
  const url = `${baseUrl}/?${getQueryParams(bibleText)}`;
  return fetch(url, {
    headers: {
      Authorization: `Token ${ESV_API_SECRET}`,
    },
  })
    .then((resp) => resp.json())
    .then((resp) => {
      logTime(Date.now());
      const { passages, canonical } = resp;
      const parsedPassage = `${passages} (${canonical})`;
      console.info('CACHE MISS', bibleText);
      cache[bibleText] = parsedPassage;
      if (areWeThrottled(resp)) {
        return { isThrottled: true, detail: resp.detail };
      }
      return new Promise((resolve) => {
        setTimeout(() => resolve({
          citedBy,
          citation: canonical,
          id: bibleText,
          bibleText: parsedPassage,
        }), esvFetchInterval);
      });
    })
    .catch((e) => {
      console.error(e);
      throw e;
    });
};

const getAllBibleVerses = (allCitations) => Object.keys(allCitations)
  .reduce((acc, c, i, srcArr) => {
    const isLast = srcArr.length === i + 1;
    return acc
      .then((data) => {
        if (data && Object.keys(data).includes('isThrottled')) {
          console.log(`We are throttled: ${data.detail}`);
          return Promise.resolve(data);
        }
        if (data) {
          return addRecordToIndex(bibleIndex, data)
            .then(() => {
              if (isLast) {
                return getBibleVerse(c, allCitations[c])
                  .then((d) => addRecordToIndex(bibleIndex, d));
              }
              return getBibleVerse(c, allCitations[c]);
            });
        }
        return getBibleVerse(c, allCitations[c]);
      })
      .catch((e) => {
        console.error('Error fetching bible verses', e);
        throw e;
      });
  }, Promise.resolve(null));

const readFile = (filePath) => {
  let data = '';
  const readStream = fs.createReadStream(filePath);
  readStream.on('data', (d) => {
    data += d;
  });
  readStream.on('end', () => {
    const parsedData = JSON.parse(data);
    // USE WHEN NOT STARTING AT THE FIRST CITATION:
    // const indexToStartAt = Object.keys(parsedData).findIndex((key) => key === lastCitationSaved) - 1;
    // const indexToStartAt = Object.keys(parsedData).findIndex((key) => key === lastCitationSaved) + 1;
    // const scripturesToParse = Object.entries(parsedData)
    //   .filter((s, i) => (i >= indexToStartAt))
    //   // .filter((s, i) => (i <= indexToStartAt))
    //   .reduce((acc, [key, value]) => ({ ...acc, [key]: value }), {});
    // console.info('starting w/ ...', Object.keys(scripturesToParse)[0]);
    getAllBibleVerses(parsedData)
      .then(() => {
        console.log('all done!');
      });
  });
};

readFile(readFrom);
