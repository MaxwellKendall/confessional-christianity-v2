import algoliasearch from 'algoliasearch';

const HITS_PER_PAGE = 1000;
const MAX_RECORDS_TO_UPDATE = Infinity;

const client = algoliasearch(process.env.ALGOLIA_API_KEY, process.env.ALGOLIA_SECRET_KEY);
const bibleIndex = client.initIndex('citations');

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
// export declare type BatchActionType = 'addObject' | 'updateObject' | 'partialUpdateObject' | 'partialUpdateObjectNoCreate' | 'deleteObject' | 'delete' | 'clear';
const action = 'partialUpdateObject';
const FIELDS_TO_UPDATE = ['startChapter', 'startVerse', 'endChapter', 'endVerse'];

const migrateRecord = (record) => {
  const body = FIELDS_TO_UPDATE.reduce((obj, field) => {
    const existingValue = record[field];
    if (existingValue === 0 || !!existingValue) {
      return {
        ...obj,
        [field]: Number(record[field])
      }
    }
    return obj;
  }, { ...record })
  return {
    action,
    body
  }
};

let page = 0;
let updatedRecords = 0;

const processHits = async (hits) => {
  if (updatedRecords >= MAX_RECORDS_TO_UPDATE) {
    console.log('fetched maximum records!');
    return Promise.resolve();
  }
  page++;
  const newRecords = hits.map(migrateRecord);
  try {
    await bibleIndex.batch(newRecords);
  } catch (e) {
    console.info('Error creating new records', newRecords);
    console.log(e);
    throw e;
  }
  updatedRecords += hits.length;
  console.log(`fetched pages: ${page} updated records: ${updatedRecords}`,);
};

const fetch = () => bibleIndex
  .browseObjects({ batch: processHits, page: 0, hitsPerPage: HITS_PER_PAGE });

fetch()
  .then(() => {
    console.info(`fetched ${page} pages`);
  });