# See Issue #36: Value not updated after changing the value of a parameter

from operator import itemgetter                                           
                                                                          
                                                                          
class Solution:                                                           
    def twoSum(self, nums: list[int], target: int) -> list[int]:          
        if len(nums) < 2:                                                 
            return nums                                                   
                                                                          
        arr = list(sorted(enumerate(nums), key=itemgetter(1)))            
        i = 0                                                             
        j = len(nums) - 1                                                 
                                                                          
        while i < j:                                                      
            arri = arr[i]                                                 
            arrj = arr[j]                                                 
            sum_ = arri[1] + arrj[1]                                      
            if sum_ == target:                                            
                return [arri[0], arrj[0]]                                 
            elif sum_ > target:                                           
                j -= 1                                                    
            else:                                                         
                i += 1                                                    
        return []                                                         
                                                                          
arr = [2, 7, 11, 15]                                                      
target = 9                                                                
                                                                          
Solution().twoSum(arr, target) == [0, 1]                                  
