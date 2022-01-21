//These are libraries which contain useful functions
#include <ctype.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <math.h>
#include <time.h>

#define MAP_SIZE 262144UL
#define MEM_LOC  0x40000000
#define FIFO_REG 0x00000024
#define FIFO_LOC 0x00000028
 
int main(int argc, char **argv)
{
  int fd;		                //File identifier
  int numSamples;	          //Number of samples to collect
  void *cfg;		            //A pointer to a memory location.  The * indicates that it is a pointer - it points to a location in memory
  char *name = "/dev/mem";	//Name of the memory resource

  uint32_t i, incr = 0;
  uint8_t saveType = 1;
  uint8_t debugflag = 0;
  uint32_t tmp;
  uint32_t *data;
  FILE *ptr;

  clock_t start, stop;


  /*
   * Parse the input arguments
   */
  int c;
  while ((c = getopt(argc,argv,"n:t:d")) != -1) {
    switch (c) {
      case 'n':
        numSamples = atoi(optarg);
        break;
      case 't':
        /*
         * Save data to command line and transmit back along TCP (0).
         * or save data into memory first then to file (1)
         * or save directly to file (2)
         */
        saveType = atoi(optarg);
        break;
      case 'd':
        //Debugging/printing flag
        debugflag = 1;
        break;

      case '?':
        if (isprint (optopt))
            fprintf (stderr, "Unknown option `-%c'.\n", optopt);
        else
            fprintf (stderr,
                    "Unknown option character `\\x%x'.\n",
                    optopt);
        return 1;

      default:
        abort();
        break;
    }
  }

  if (saveType == 2) {
    //Clear file and open for writing if saving to file directly
    ptr = fopen("SavedData.bin","wb");
  } else {
    data = (uint32_t *) malloc(numSamples * sizeof(uint32_t));
    if (!data) {
      printf("Error allocating memory");
      return -1;
    }
  }
  

  //This returns a file identifier corresponding to the memory, and allows for reading and writing.  O_RDWR is just a constant
  if((fd = open(name, O_RDWR)) < 0) {
    perror("open");
    return 1;
  }

  /*mmap maps the memory location 0x40000000 to the pointer cfg, which "points" to that location in memory.*/
  cfg = mmap(0,MAP_SIZE,PROT_READ|PROT_WRITE,MAP_SHARED,fd,MEM_LOC);
  /*
   * Disable FIFO and then reset
   */
  *((uint32_t *)(cfg + FIFO_REG)) = 0;
  *((uint32_t *)(cfg + FIFO_REG)) = 2;
  *((uint32_t *)(cfg + FIFO_REG)) = 0;
  usleep(1);
  /*
   * Enable FIFO and record data
   */
  *((uint32_t *)(cfg + FIFO_REG)) = 1;
  if (saveType == 1 | saveType == 2) {
    /*
     * These save types don't write to standard out,
     * so they can print debugging information
     */
    start = clock();
  }
  
  if (saveType != 2) {
    /*
     * Save data to a memory location
     */
    for (i = 0;i<numSamples;i++) {
      *(data + i) = *((uint32_t *)(cfg + FIFO_LOC));
    }
  } else {
    /*
     * Save data directly to file
     */
    for (i = 0;i<numSamples;i++) {
        tmp = *((uint32_t *)(cfg + FIFO_LOC));
        fwrite(&tmp,4,1,ptr);
    }
  }
  
  /*
   * Disable FIFO and print debugging information
   */
  *((uint32_t *)(cfg + FIFO_REG)) = 0;
  if ((saveType == 1 | saveType == 2) & (debugflag == 1)) {
    stop = clock();
    printf("Execution time: %.3f ms\n",(double)(stop - start)/CLOCKS_PER_SEC*1e3);
    printf("Time per read: %.3f us\n",(double)(stop - start)/CLOCKS_PER_SEC/(double)(numSamples)*1e6);
  }

  if (saveType == 0) {
    for (i = 0;i<numSamples;i++) {
        printf("%08x\n",*(data + i));
    }
    free(data);
  } else if (saveType == 1) {
    ptr = fopen("SavedData.bin","wb");
    fwrite(data,4,(size_t)(numSamples),ptr);
    fclose(ptr);
    free(data);
  } else if (saveType == 2) {
    fclose(ptr);
  }

  //Unmap cfg from pointing to the previous location in memory
  munmap(cfg, MAP_SIZE);
  return 0;	//C functions should have a return value - 0 is the usual "no error" return value
}
