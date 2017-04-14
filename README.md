# Caffe-FastFPBP

This code mainly targets at reproducing the results in "Efficient Lung Cancer Cell Detection with Deep Convolution Neural Network". The pre-trained model and the accelerated network definition can be found in `/models/zx_lenet_is`. This implementation is based on [caffe](http://caffe.berkeleyvision.org/) 1.0. 

Free free to cite us if you think our code help your research. 

    @incollection{xu2015efficient,
    	title={Efficient Lung Cancer Cell Detection with Deep Convolution Neural Network},
    	editor={Wu, Guorong and Coup{\'e}, Pierrick and Zhan, Yiqiang and Munsell, Brent and Rueckert, Daniel},
    	author={Xu, Zheng and Huang, Junzhou},
    	booktitle={Patch-MI},
    	pages={79--86},
    	year={2015},
    	publisher={Springer International Publishing}
    }

Our following paper is also based on this implementation, which you might also want to take a look.

@inproceedings{xu2016detecting,
  title={Detecting 10,000 Cells in One Second},
  author={Xu, Zheng and Huang, Junzhou},
  booktitle={International Conference on Medical Image Computing and Computer-Assisted Intervention},
  pages={676--684},
  year={2016},
  organization={Springer}
}