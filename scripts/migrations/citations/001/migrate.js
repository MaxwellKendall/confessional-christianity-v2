import algoliasearch from 'algoliasearch';

const HITS_PER_PAGE = 1000;

const client = algoliasearch(process.env.ALGOLIA_API_KEY, process.env.ALGOLIA_SECRET_KEY);
const bibleIndex = client.initIndex('bible verses');
const bibleIndexV2 = client.initIndex('citations');

/**
 * v1:
 * {
 *   citedBy: string[],
 *   bibleText: string,
 *   citation: string,
 *   id: string
 * }
 * v2:
 * {
 *   citedBy: string[],
 *   bibleText: string,
 *   citation: string,
 *   book: string,
 *   startChapter: number,
 *   endChapter: number,
 *   startVerse: number,
 *   endVerse: number,
 *   id: string
 * }
 */
const action = 'addObject';

const migrateRecord = (record) => {
  const { id } = record;
  const range = id.split('-');
  if (range.length > 1) {
    const [start, end] = range;
    const [book, startChapter, startVerse] = start.split('.');
    const [, endChapter, endVerse] = end.split('.');
    const rtrn = {
      ...record,
      book,
      startChapter,
      startVerse,
      endChapter,
      endVerse,
    };
    return { action, body: rtrn };
  }
  const [book, startChapter, startVerse] = id.split('.');
  return {
    action,
    body: {
      ...record,
      book,
      startChapter,
      endChapter: startChapter,
      startVerse,
      endVerse: startVerse,
    },
  };
};

let page = 1;

const processHits = async (hits) => {
  page++;
  console.log(`fetched pages: ${page}`);
  const newRecords = hits.map(migrateRecord);
  try {
    await bibleIndexV2.batch(newRecords);
  } catch (e) {
    console.info('Error creating new records', newRecords);
    console.log(e);
    throw e;
  }
};

const fetch = () => bibleIndex
  .browseObjects({ batch: processHits, page: 0, hitsPerPage: HITS_PER_PAGE });

fetch()
  .then(() => {
    console.info(`fetched ${page} pages`);
  });